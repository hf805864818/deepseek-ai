import Foundation
import os.log

private let logger = AppLogger(category: "GoogleDriveAPI")

// MARK: - File Model

struct GoogleDriveFile: Codable {
    let id: String
    let name: String
    let mimeType: String
    let modifiedTime: Date?
    let size: Int64?
    let md5Checksum: String?

    init(
        id: String,
        name: String,
        mimeType: String,
        modifiedTime: Date? = nil,
        size: Int64? = nil,
        md5Checksum: String? = nil
    ) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.modifiedTime = modifiedTime
        self.size = size
        self.md5Checksum = md5Checksum
    }

    enum CodingKeys: String, CodingKey {
        case id, name, mimeType, modifiedTime, size, md5Checksum
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType) ?? ""
        if let ts = try c.decodeIfPresent(String.self, forKey: .modifiedTime) {
            modifiedTime = GoogleDriveFile.parseDate(ts)
        } else {
            modifiedTime = nil
        }
        if let s = try c.decodeIfPresent(String.self, forKey: .size) {
            size = Int64(s)
        } else {
            size = nil
        }
        md5Checksum = try c.decodeIfPresent(String.self, forKey: .md5Checksum)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(mimeType, forKey: .mimeType)
        if let mt = modifiedTime {
            try c.encode(GoogleDriveFile.dateFormatter.string(from: mt), forKey: .modifiedTime)
        }
        if let s = size {
            try c.encode(String(s), forKey: .size)
        }
        try c.encodeIfPresent(md5Checksum, forKey: .md5Checksum)
    }

    // MARK: - Date Parsing

    /// ISO 8601 / RFC 3339 formatter with fractional seconds (Google Drive format).
    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Fallback formatter without fractional seconds.
    private static let dateFormatterNoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parses a Google Drive date string, handling both with and without
    /// fractional seconds.
    fileprivate static func parseDate(_ string: String) -> Date? {
        if let d = dateFormatter.date(from: string) { return d }
        return dateFormatterNoFractional.date(from: string)
    }
}

// MARK: - API Client

/// Google Drive REST API v3 client.
/// Uses GoogleDriveOAuthManager.shared for authentication.
/// All methods are async and throw on error.
enum GoogleDriveAPI {

    private static let baseURL = "https://www.googleapis.com/drive/v3"
    private static let uploadURL = "https://www.googleapis.com/upload/drive/v3"

    // MARK: - Folder Operations

    /// Creates a folder in Google Drive. Returns the new folder's file ID.
    static func createFolder(name: String, parentId: String?) async throws -> String {
        logger.info("createFolder: \(name)")
        var metadata: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder",
        ]
        if let parentId = parentId {
            metadata["parents"] = [parentId]
        }

        let body = try JSONSerialization.data(withJSONObject: metadata)
        var request = try await authorizedRequest(
            url: "\(baseURL)/files",
            method: "POST",
            contentType: "application/json; charset=UTF-8"
        )
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data, context: "createFolder")

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let fileId = json["id"] as? String else {
            throw LLMError.decodingError(underlying: NSError(
                domain: "GoogleDriveAPI", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing folder ID in response"]
            ))
        }
        logger.info("createFolder success: \(fileId)")
        return fileId
    }

    /// Finds a folder by name in the app data folder, or creates it if not found.
    /// Uses the special "appDataFolder" space which requires the drive.appdata scope.
    static func findOrCreateFolder(name: String) async throws -> String {
        logger.info("findOrCreateFolder: \(name)")

        // Strategy: try direct create first (idempotent-ish — duplicates are
        // harmless for backup use case), then fall back to search+create.
        // We used to search first, but search 403s are harder to diagnose than
        // create 403s — and if the folder already exists, create will also
        // fail with a clear error that we can handle.
        //
        // Actual flow: search first (cheap read), then create. But we wrap
        // search in a try? so a search failure doesn't block the create path.

        // 1. Try searching first
        do {
            let q = "mimeType = 'application/vnd.google-apps.folder' and name = '\(name)' and trashed = false"
            var components = URLComponents(string: "\(baseURL)/files")!
            components.queryItems = [
                URLQueryItem(name: "q", value: q),
                URLQueryItem(name: "fields", value: "files(id, name)"),
                URLQueryItem(name: "pageSize", value: "10"),
                URLQueryItem(name: "spaces", value: "appDataFolder"),
            ]

            let request = try await authorizedRequest(
                url: components.url!.absoluteString,
                method: "GET"
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            try checkResponse(response, data: data, context: "findOrCreateFolder search")

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let files = json["files"] as? [[String: Any]] ?? []

            if let first = files.first, let id = first["id"] as? String {
                logger.info("findOrCreateFolder: found existing folder \(id)")
                return id
            }
        } catch {
            // Search failed — log and fall through to create attempt
            logger.warning("findOrCreateFolder: search failed (\(error.localizedDescription)) — trying direct create")
        }

        // 2. Search failed or not found — create it in app data folder
        return try await createFolder(name: name, parentId: "appDataFolder")
    }

    // MARK: - File Upload

    /// Uploads a file using multipart upload (for files <= 5 MB).
    /// Returns the new file's ID.
    static func uploadFile(
        name: String,
        data: Data,
        parentId: String,
        mimeType: String
    ) async throws -> String {
        logger.info("uploadFile: \(name) (\(data.count) bytes)")

        let boundary = "minis_drive_\(UUID().uuidString)"
        let metadata: [String: Any] = [
            "name": name,
            "parents": [parentId],
        ]

        var body = Data()
        // Metadata part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(try JSONSerialization.data(withJSONObject: metadata))
        body.append("\r\n".data(using: .utf8)!)
        // File data part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = try await authorizedRequest(
            url: "\(uploadURL)/files?uploadType=multipart&fields=id",
            method: "POST",
            contentType: "multipart/related; boundary=\(boundary)"
        )
        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: responseData, context: "uploadFile")

        let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] ?? [:]
        guard let fileId = json["id"] as? String else {
            throw LLMError.decodingError(underlying: NSError(
                domain: "GoogleDriveAPI", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing file ID in upload response"]
            ))
        }
        logger.info("uploadFile success: \(fileId)")
        return fileId
    }

    /// Uploads a file using resumable upload (for large files > 5 MB).
    /// Starts a resumable session, then uploads data in 5 MB chunks.
    /// Calls progressHandler with values from 0.0 to 1.0.
    /// Returns the new file's ID.
    static func uploadFileResumable(
        name: String,
        data: Data,
        parentId: String,
        mimeType: String,
        progressHandler: ((Double) -> Void)?
    ) async throws -> String {
        logger.info("uploadFileResumable: \(name) (\(data.count) bytes)")

        let metadata: [String: Any] = [
            "name": name,
            "parents": [parentId],
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)

        // 1. Start resumable session to get session URI
        var sessionRequest = try await authorizedRequest(
            url: "\(uploadURL)/files?uploadType=resumable&fields=id",
            method: "POST",
            contentType: "application/json; charset=UTF-8"
        )
        sessionRequest.setValue(mimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        sessionRequest.setValue("\(data.count)", forHTTPHeaderField: "X-Upload-Content-Length")
        sessionRequest.httpBody = metadataData

        let (_, sessionResponse) = try await URLSession.shared.data(for: sessionRequest)
        guard let sessionHTTP = sessionResponse as? HTTPURLResponse,
              (200..<300).contains(sessionHTTP.statusCode) else {
            throw LLMError.providerError(message: "Failed to start resumable session")
        }
        guard let sessionURI = sessionHTTP.value(forHTTPHeaderField: "Location") else {
            throw LLMError.providerError(message: "Missing session URI (Location header)")
        }
        logger.info("Resumable session URI obtained")

        // 2. Upload data in 5 MB chunks
        let chunkSize = 5 * 1024 * 1024 // 5 MB
        let totalSize = data.count
        var offset = 0
        var fileId: String?

        progressHandler?(0.0)

        while offset < totalSize {
            let end = min(offset + chunkSize, totalSize)
            let chunk = data[offset..<end]
            let chunkLength = end - offset
            let isLast = end >= totalSize

            var chunkRequest = URLRequest(url: URL(string: sessionURI)!)
            chunkRequest.httpMethod = "PUT"
            chunkRequest.setValue("\(chunkLength)", forHTTPHeaderField: "Content-Length")
            chunkRequest.setValue(
                "bytes \(offset)-\(end - 1)/\(totalSize)",
                forHTTPHeaderField: "Content-Range"
            )
            chunkRequest.httpBody = Data(chunk)

            let (responseData, chunkResponse) = try await URLSession.shared.data(for: chunkRequest)
            guard let chunkHTTP = chunkResponse as? HTTPURLResponse else {
                throw LLMError.providerError(message: "Invalid chunk response")
            }

            if (200..<300).contains(chunkHTTP.statusCode) {
                // Upload complete — parse file ID from response
                let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] ?? [:]
                fileId = json["id"] as? String
                progressHandler?(1.0)
                break
            } else if chunkHTTP.statusCode == 308 {
                // Resume incomplete — continue with next chunk
                offset = end
                let progress = Double(offset) / Double(totalSize)
                progressHandler?(progress)
            } else {
                throw LLMError.providerError(
                    message: "Upload failed at offset \(offset) (status \(chunkHTTP.statusCode))"
                )
            }
        }

        guard let id = fileId else {
            throw LLMError.providerError(message: "Upload completed but no file ID returned")
        }
        logger.info("uploadFileResumable success: \(id)")
        return id
    }

    // MARK: - File Download

    /// Downloads a file's binary content by its ID.
    static func downloadFile(fileId: String) async throws -> Data {
        logger.info("downloadFile: \(fileId)")

        let request = try await authorizedRequest(
            url: "\(baseURL)/files/\(fileId)?alt=media",
            method: "GET"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data, context: "downloadFile(\(fileId))")
        logger.info("downloadFile success: \(data.count) bytes")
        return data
    }

    // MARK: - File Listing

    /// Lists files in a parent folder (or app data folder root if parentId is nil).
    /// When parentId is "appDataFolder" or nil, uses the appDataFolder space.
    static func listFiles(parentId: String?, pageSize: Int = 100) async throws -> [GoogleDriveFile] {
        logger.info("listFiles: parentId=\(parentId ?? "appDataFolder")")

        let useAppDataSpace = parentId == nil || parentId == "appDataFolder"
        var q = "trashed = false"
        if let parentId = parentId, parentId != "appDataFolder" {
            q = "trashed = false and '\(parentId)' in parents"
        }

        var components = URLComponents(string: "\(baseURL)/files")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "pageSize", value: "\(pageSize)"),
            URLQueryItem(
                name: "fields",
                value: "files(id, name, mimeType, modifiedTime, size, md5Checksum)"
            ),
            URLQueryItem(name: "q", value: q),
        ]
        if useAppDataSpace {
            queryItems.append(URLQueryItem(name: "spaces", value: "appDataFolder"))
        }
        components.queryItems = queryItems

        let request = try await authorizedRequest(
            url: components.url!.absoluteString,
            method: "GET"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data, context: "listFiles")

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let files = json["files"] as? [[String: Any]] ?? []

        let result: [GoogleDriveFile] = files.compactMap { dict in
            guard let id = dict["id"] as? String,
                  let name = dict["name"] as? String else { return nil }
            let mimeType = dict["mimeType"] as? String ?? ""
            let modifiedTime: Date? = {
                guard let ts = dict["modifiedTime"] as? String else { return nil }
                return GoogleDriveFile.parseDate(ts)
            }()
            let size = (dict["size"] as? String).flatMap { Int64($0) }
            let md5 = dict["md5Checksum"] as? String
            return GoogleDriveFile(
                id: id, name: name, mimeType: mimeType,
                modifiedTime: modifiedTime, size: size, md5Checksum: md5
            )
        }

        logger.info("listFiles success: \(result.count) files")
        return result
    }

    // MARK: - File Deletion

    /// Permanently deletes a file by its ID.
    static func deleteFile(fileId: String) async throws {
        logger.info("deleteFile: \(fileId)")

        let request = try await authorizedRequest(
            url: "\(baseURL)/files/\(fileId)",
            method: "DELETE"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data, context: "deleteFile(\(fileId))")
        logger.info("deleteFile success: \(fileId)")
    }

    // MARK: - File Metadata

    /// Gets metadata for a single file by its ID.
    static func getFileMetadata(fileId: String) async throws -> GoogleDriveFile {
        logger.info("getFileMetadata: \(fileId)")

        var components = URLComponents(string: "\(baseURL)/files/\(fileId)")!
        components.queryItems = [
            URLQueryItem(
                name: "fields",
                value: "id, name, mimeType, modifiedTime, size, md5Checksum"
            ),
        ]

        let request = try await authorizedRequest(
            url: components.url!.absoluteString,
            method: "GET"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponse(response, data: data, context: "getFileMetadata(\(fileId))")

        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let id = dict["id"] as? String,
              let name = dict["name"] as? String else {
            throw LLMError.decodingError(underlying: NSError(
                domain: "GoogleDriveAPI", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing file metadata fields"]
            ))
        }

        let mimeType = dict["mimeType"] as? String ?? ""
        let modifiedTime: Date? = {
            guard let ts = dict["modifiedTime"] as? String else { return nil }
            return GoogleDriveFile.parseDate(ts)
        }()
        let size = (dict["size"] as? String).flatMap { Int64($0) }
        let md5 = dict["md5Checksum"] as? String

        return GoogleDriveFile(
            id: id, name: name, mimeType: mimeType,
            modifiedTime: modifiedTime, size: size, md5Checksum: md5
        )
    }

    // MARK: - Private Helpers

    /// Builds an authorized URLRequest with the Bearer token from the OAuth
    /// manager. Refreshes the token if necessary.
    private static func authorizedRequest(
        url urlString: String,
        method: String,
        contentType: String? = nil
    ) async throws -> URLRequest {
        guard let url = URL(string: urlString) else {
            throw LLMError.providerError(message: "Invalid URL: \(urlString)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        let token = try await GoogleDriveOAuthManager.shared.validAccessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let contentType = contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// Checks an HTTP response for success status code. Throws on failure.
    /// Parses Google Drive API error responses to include the actual error
    /// message (e.g. "insufficientPermissions", "rateLimitExceeded") so users
    /// can understand *why* a 403/429 happened instead of just the status code.
    private static func checkResponse(
        _ response: URLResponse,
        data: Data,
        context: String
    ) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.providerError(message: "\(context): invalid response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            // Try to parse Google's standard error JSON format
            let errorDetail = Self.parseGoogleError(data: data)
            logger.error("\(context) FAILED — status \(http.statusCode): \(errorDetail ?? String(body.prefix(300)))")

            let userMessage = errorDetail ?? "HTTP \(http.statusCode)"
            throw LLMError.providerError(
                message: "\(context) failed (\(userMessage))"
            )
        }
    }

    /// Parses a Google Drive API error response and returns a human-readable
    /// error string (reason + message). Returns nil if parsing fails.
    private static func parseGoogleError(data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else {
            return nil
        }

        let code = (error["code"] as? Int) ?? 0
        let message = (error["message"] as? String) ?? ""
        // Extract the first error's "reason" field if available
        let reason: String
        if let errors = error["errors"] as? [[String: Any]],
           let first = errors.first,
           let r = first["reason"] as? String {
            reason = r
        } else {
            reason = "status \(code)"
        }

        if message.isEmpty {
            return reason
        }
        return "\(reason): \(message)"
    }
}
