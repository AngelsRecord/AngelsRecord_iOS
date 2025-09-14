//
//  NCPDownloader.swift
//  A'Cast
//
//  Created by 성현 on 9/9/25.
//

import Foundation
import AWSS3

final class NCPDownloader {

    struct Config {
        let endpoint: String
        let bucket: String
        let keyPrefix: String      // 예: "audios"
        let accessKey: String
        let secretKey: String
        /// 파일 확장자를 소문자로 정규화할지 (".MP3" → ".mp3")
        let normalizeExtensionLowercased: Bool

        init(endpoint: String,
             bucket: String,
             keyPrefix: String,
             accessKey: String,
             secretKey: String,
             normalizeExtensionLowercased: Bool = true) {
            self.endpoint = endpoint
            self.bucket = bucket
            self.keyPrefix = keyPrefix
            self.accessKey = accessKey
            self.secretKey = secretKey
            self.normalizeExtensionLowercased = normalizeExtensionLowercased
        }
    }

    private let cfg: Config
    private let transferKey = "ncp.transfer"

    init(cfg: Config) {
        self.cfg = cfg

        let credentials = AWSStaticCredentialsProvider(
            accessKey: cfg.accessKey,
            secretKey: cfg.secretKey
        )
        guard let endpoint = AWSEndpoint(urlString: cfg.endpoint),
              let serviceConfig = AWSServiceConfiguration(
                  region: .APNortheast2, // endpoint가 실권
                  endpoint: endpoint,
                  credentialsProvider: credentials
              ) else {
            fatalError("AWSServiceConfiguration 생성 실패")
        }

        let tuConfig = AWSS3TransferUtilityConfiguration()
        tuConfig.isAccelerateModeEnabled = false

        AWSS3TransferUtility.register(
            with: serviceConfig,
            transferUtilityConfiguration: tuConfig,
            forKey: transferKey
        )
    }

    private func joinKey(prefix: String, fileName: String) -> String {
        let p = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let f = fileName.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return p.isEmpty ? f : "\(p)/\(f)"
    }

    private func normalizeFileName(_ fileName: String) -> String {
        guard cfg.normalizeExtensionLowercased else { return fileName }
        let ns = fileName as NSString
        let ext = ns.pathExtension
        guard !ext.isEmpty else { return fileName }
        let base = ns.deletingPathExtension
        return "\(base).\(ext.lowercased())"
    }

    /// 단일 파일 다운로드
    func download(
        fileName: String,
        progress: ((Double) -> Void)? = nil,
        completion: @escaping (Result<(localURL: URL, bytesPerSec: Double), Error>) -> Void
    ) {
        guard let transfer = AWSS3TransferUtility.s3TransferUtility(forKey: transferKey) else {
            completion(.failure(NSError(
                domain: "NCPDownloader",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "TransferUtility 키 조회 실패"]
            )))
            return
        }

        let normalized = normalizeFileName(fileName)
        let key = joinKey(prefix: cfg.keyPrefix, fileName: normalized)

        let localURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent(normalized, isDirectory: false)

        try? FileManager.default.removeItem(at: localURL)

        let exp = AWSS3TransferUtilityDownloadExpression()
        let start = CFAbsoluteTimeGetCurrent()
        var totalExpected: Int64 = 0

        exp.progressBlock = { _, prog in
            totalExpected = prog.totalUnitCount
            progress?(prog.fractionCompleted)
        }

        transfer.download(to: localURL, bucket: cfg.bucket, key: key, expression: exp) { task, _, _, error in
            let end = CFAbsoluteTimeGetCurrent()

            if let http = task.response as? HTTPURLResponse {
                if !(200...299).contains(http.statusCode) {
                    let err = NSError(
                        domain: "NCPDownloader",
                        code: http.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]
                    )
                    completion(.failure(err))
                    return
                }
            }
            if let error = error {
                completion(.failure(error))
                return
            }

            let elapsed = max(end - start, 0.0001)
            let fileSize = (try? FileManager.default
                .attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? totalExpected
            let bytesPerSec = Double(fileSize) / elapsed

            completion(.success((localURL, bytesPerSec)))
        }
        .continueWith { task in
            if let err = task.error as NSError? {
                completion(.failure(err))
            }
            return nil
        }
    }
}
