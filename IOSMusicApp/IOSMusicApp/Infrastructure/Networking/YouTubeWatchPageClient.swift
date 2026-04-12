import Foundation
import OSLog

protocol YouTubePlayerResponseProviding {
    func fetchPlayerResponse(forVideoID videoID: String) async throws -> YouTubePlayerResponseDTO
}

struct YouTubeWatchPageClient: YouTubePlayerResponseProviding {
    enum ClientError: Error, Equatable, LocalizedError {
        case invalidRequestURL
        case transportFailure
        case invalidResponse(Int?)
        case missingPlayerResponse
        case decodingFailure

        var errorDescription: String? {
            switch self {
            case .invalidRequestURL:
                return "The YouTube watch-page request URL was invalid."
            case .transportFailure:
                return "The YouTube watch page could not be loaded."
            case .invalidResponse(let statusCode):
                if let statusCode {
                    return "The YouTube watch page returned an invalid response (HTTP \(statusCode))."
                }
                return "The YouTube watch page returned an invalid response."
            case .missingPlayerResponse:
                return "The YouTube watch page did not expose a player response."
            case .decodingFailure:
                return "The YouTube player response could not be decoded."
            }
        }
    }

    private let session: URLSession
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "YouTubeWatchPageClient")

    init(
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.session = session
        self.decoder = decoder
    }

    func fetchPlayerResponse(forVideoID videoID: String) async throws -> YouTubePlayerResponseDTO {
        guard let requestURL = watchPageURL(forVideoID: videoID) else {
            logger.error("Could not build watch-page request URL for \(videoID, privacy: .public)")
            throw ClientError.invalidRequestURL
        }

        var request = URLRequest(url: requestURL)
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            logger.error("Watch-page transport failed for \(videoID, privacy: .public): \(String(describing: error), privacy: .public)")
            throw ClientError.transportFailure
        }

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode,
              let html = String(data: data, encoding: .utf8) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            logger.error("Watch-page returned invalid response for \(videoID, privacy: .public): HTTP \(statusCode ?? -1, privacy: .public)")
            throw ClientError.invalidResponse(statusCode)
        }

        do {
            return try decodePlayerResponse(fromHTML: html)
        } catch let error as ClientError {
            logClientError(error, videoID: videoID)
            throw error
        } catch {
            logger.error("Unexpected player-response parse failure for \(videoID, privacy: .public): \(String(describing: error), privacy: .public)")
            throw ClientError.decodingFailure
        }
    }

    func decodePlayerResponse(fromHTML html: String) throws -> YouTubePlayerResponseDTO {
        guard let playerResponseJSON = extractPlayerResponseJSON(from: html),
              let jsonData = playerResponseJSON.data(using: .utf8) else {
            throw ClientError.missingPlayerResponse
        }

        do {
            return try decoder.decode(YouTubePlayerResponseDTO.self, from: jsonData)
        } catch {
            throw ClientError.decodingFailure
        }
    }

    private func watchPageURL(forVideoID videoID: String) -> URL? {
        var components = URLComponents(string: "https://www.youtube.com/watch")
        components?.queryItems = [
            URLQueryItem(name: "v", value: videoID),
            URLQueryItem(name: "hl", value: "en"),
            URLQueryItem(name: "bpctr", value: "9999999999"),
            URLQueryItem(name: "has_verified", value: "1")
        ]
        return components?.url
    }

    private func extractPlayerResponseJSON(from html: String) -> String? {
        let tokens = [
            "ytInitialPlayerResponse",
            "window[\"ytInitialPlayerResponse\"]",
            "window['ytInitialPlayerResponse']"
        ]

        for token in tokens {
            if let json = extractAssignedPlayerResponse(after: token, in: html) {
                return json
            }
        }

        return nil
    }

    private func extractAssignedPlayerResponse(after token: String, in html: String) -> String? {
        var searchStartIndex = html.startIndex

        while let tokenRange = html.range(of: token, range: searchStartIndex..<html.endIndex) {
            let searchRange = tokenRange.upperBound..<html.endIndex
            guard let equalsIndex = html[searchRange].firstIndex(of: "=") else {
                searchStartIndex = tokenRange.upperBound
                continue
            }

            let valueStartIndex = html.index(after: equalsIndex)
            if let extractedValue = extractAssignedValue(in: html, from: valueStartIndex) {
                return extractedValue
            }

            searchStartIndex = tokenRange.upperBound
        }

        return nil
    }

    private func extractAssignedValue(in html: String, from startIndex: String.Index) -> String? {
        guard let firstValueIndex = html[startIndex...].firstIndex(where: { !$0.isWhitespace }) else {
            return nil
        }

        if html[firstValueIndex] == "{",
           let closingBraceIndex = balancedJSONObjectEndIndex(in: html, from: firstValueIndex) {
            return String(html[firstValueIndex...closingBraceIndex])
        }

        let remainingText = html[firstValueIndex...]
        guard remainingText.hasPrefix("JSON.parse(") else {
            return nil
        }

        let parseArgumentStart = html.index(firstValueIndex, offsetBy: "JSON.parse(".count)
        return extractJSONStringLiteral(from: html, startingAt: parseArgumentStart)
    }

    private func extractJSONStringLiteral(from html: String, startingAt startIndex: String.Index) -> String? {
        guard let openingQuoteIndex = html[startIndex...].firstIndex(where: { !$0.isWhitespace }),
              html[openingQuoteIndex] == "\"" || html[openingQuoteIndex] == "'" else {
            return nil
        }

        let quoteCharacter = html[openingQuoteIndex]
        var currentIndex = html.index(after: openingQuoteIndex)
        var isEscaping = false

        while currentIndex < html.endIndex {
            let character = html[currentIndex]

            if isEscaping {
                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else if character == quoteCharacter {
                let literalRange = openingQuoteIndex...currentIndex
                return decodeJavaScriptStringLiteral(String(html[literalRange]))
            }

            currentIndex = html.index(after: currentIndex)
        }

        return nil
    }

    private func decodeJavaScriptStringLiteral(_ literal: String) -> String? {
        guard literal.count >= 2,
              let quoteCharacter = literal.first,
              literal.last == quoteCharacter else {
            return nil
        }

        let content = literal.dropFirst().dropLast()
        var result = ""
        var iterator = content.makeIterator()
        var isEscaping = false

        while let character = iterator.next() {
            if !isEscaping {
                if character == "\\" {
                    isEscaping = true
                } else {
                    result.append(character)
                }
                continue
            }

            switch character {
            case "\\", "/", "\"", "'":
                result.append(character)
            case "b":
                result.append("\u{0008}")
            case "f":
                result.append("\u{000C}")
            case "n":
                result.append("\n")
            case "r":
                result.append("\r")
            case "t":
                result.append("\t")
            case "u":
                var scalarDigits = ""
                for _ in 0..<4 {
                    guard let nextDigit = iterator.next() else {
                        return nil
                    }
                    scalarDigits.append(nextDigit)
                }
                guard let scalarValue = UInt32(scalarDigits, radix: 16),
                      let scalar = UnicodeScalar(scalarValue) else {
                    return nil
                }
                result.append(Character(scalar))
            default:
                result.append(character)
            }

            isEscaping = false
        }

        return isEscaping ? nil : result
    }

    private func balancedJSONObjectEndIndex(in text: String, from openingBraceIndex: String.Index) -> String.Index? {
        var currentIndex = openingBraceIndex
        var depth = 0
        var isInsideString = false
        var isEscaping = false

        while currentIndex < text.endIndex {
            let character = text[currentIndex]

            if isEscaping {
                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else if character == "\"" {
                isInsideString.toggle()
            } else if !isInsideString {
                if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1

                    if depth == 0 {
                        return currentIndex
                    }
                }
            }

            currentIndex = text.index(after: currentIndex)
        }

        return nil
    }

    private func logClientError(_ error: ClientError, videoID: String) {
        switch error {
        case .invalidRequestURL:
            logger.error("Invalid watch-page request URL for \(videoID, privacy: .public)")
        case .transportFailure:
            logger.error("Watch-page fetch failed for \(videoID, privacy: .public)")
        case .invalidResponse(let statusCode):
            logger.error("Watch-page invalid response for \(videoID, privacy: .public): HTTP \(statusCode ?? -1, privacy: .public)")
        case .missingPlayerResponse:
            logger.error("Player response parse failure for \(videoID, privacy: .public): missing player response")
        case .decodingFailure:
            logger.error("Player response parse failure for \(videoID, privacy: .public): malformed JSON")
        }
    }
}
