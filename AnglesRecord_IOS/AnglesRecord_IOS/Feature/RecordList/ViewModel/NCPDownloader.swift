//
//  NCPDownloader.swift
//  A'Cast
//
//  Created by 성현 on 9/9/25.
//

import Foundation
import AWSS3

/// Naver Cloud Object Storage (S3 compatible) downloader + metadata helpers
final class NCPDownloader {

    // MARK: - Public Config
    struct Config {
        let endpoint: String        // e.g. "https://kr.object.ncloudstorage.com"
        let bucket: String
        let keyPrefix: String       // e.g. "audios" (no leading/trailing slash)
        let accessKey: String
        let secretKey: String
        /// Normalize file extension to lowercase (".MP3" → ".mp3")
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

    // MARK: - Keys & State
    private let cfg: Config
    private let transferKey = "ncp.transfer"
    private let s3Key       = "ncp.s3"
    private let presignKey  = "ncp.presign"
    
    private let syncQ = DispatchQueue(label: "ncp.downloader.sync")
    private var downloadTasks: [String: AWSS3TransferUtilityDownloadTask] = [:]

    // MARK: - Init
    init(cfg: Config) {
        // 1) Endpoint sanitize (scheme 보장, 말단 슬래시 제거)
        var fixed = cfg
        fixed = .init(
            endpoint: Self.sanitizeEndpoint(cfg.endpoint),
            bucket: cfg.bucket,
            keyPrefix: cfg.keyPrefix,
            accessKey: cfg.accessKey,
            secretKey: cfg.secretKey,
            normalizeExtensionLowercased: cfg.normalizeExtensionLowercased
        )
        self.cfg = fixed

        let credentials = AWSStaticCredentialsProvider(
            accessKey: fixed.accessKey,
            secretKey: fixed.secretKey
        )

        guard let endpoint = AWSEndpoint(urlString: fixed.endpoint),
              let serviceConfig = AWSServiceConfiguration(
                region: .APNortheast2, // endpoint override 사용
                endpoint: endpoint,
                credentialsProvider: credentials
              ) else {
            fatalError("AWSServiceConfiguration 생성 실패 (endpoint=\(fixed.endpoint))")
        }

        // DEBUG
        print("🔧 NCP init endpoint=\(fixed.endpoint), bucket=\(fixed.bucket), prefix=\(fixed.keyPrefix)")

        // 2) Register clients
        let tuConfig = AWSS3TransferUtilityConfiguration()
        tuConfig.isAccelerateModeEnabled = false
        AWSS3TransferUtility.register(
            with: serviceConfig,
            transferUtilityConfiguration: tuConfig,
            forKey: transferKey
        )
        AWSS3.register(with: serviceConfig, forKey: s3Key)
        AWSS3PreSignedURLBuilder.register(with: serviceConfig, forKey: presignKey)
    }

    // MARK: - Public API

    /// Download single file to Caches, return localURL & throughput
    func download(
        fileName: String,
        progress: ((Double) -> Void)? = nil,
        completion: @escaping (Result<(localURL: URL, bytesPerSec: Double), Error>) -> Void
    ) {
        guard let transfer = AWSS3TransferUtility.s3TransferUtility(forKey: transferKey) else {
            completion(.failure(NSError(domain: "NCPDownloader", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: "TransferUtility 키 조회 실패"])))
            return
        }

        let normalized = normalizeFileName(fileName)
        let key = joinKey(prefix: cfg.keyPrefix, fileName: normalized)

        let localURL = cachesURL(for: normalized)
        try? FileManager.default.removeItem(at: localURL)

        let exp = AWSS3TransferUtilityDownloadExpression()
        let start = CFAbsoluteTimeGetCurrent()
        var totalExpected: Int64 = 0

        exp.progressBlock = { _, prog in
            totalExpected = prog.totalUnitCount
            progress?(prog.fractionCompleted)
        }

        // ⬇️ 태스크 핸들 확보/보관
        let taskAWSTask = transfer.download(to: localURL, bucket: cfg.bucket, key: key, expression: exp) { task, _, _, error in
            // 완료/실패 시 보관 해제
            self.syncQ.async { self.downloadTasks.removeValue(forKey: normalized) }

            let end = CFAbsoluteTimeGetCurrent()

            if let http = task.response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                let err = NSError(domain: "NCPDownloader", code: http.statusCode,
                                  userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
                completion(.failure(err))
                return
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

        // 태스크 생성 결과 저장(에러면 여기서 리턴)
        taskAWSTask.continueWith { t in
            if let err = t.error {
                completion(.failure(err))
            } else if let dlTask = t.result {
                self.syncQ.async { self.downloadTasks[normalized] = dlTask }
            }
            return nil
        }
    }

    /// 진행 중인 단일 파일 다운로드 취소. removePartial=true면 Caches의 부분 파일 삭제.
    func cancel(fileName: String, removePartial: Bool = true, completion: (() -> Void)? = nil) {
        let normalized = normalizeFileName(fileName)
        let key = joinKey(prefix: cfg.keyPrefix, fileName: normalized)

        // 1) 보관 중인 태스크 취소
        var canceled = false
        syncQ.sync {
            if let t = downloadTasks.removeValue(forKey: normalized) {
                t.cancel()
                canceled = true
            }
        }

        // 2) 보관 딕셔너리에 없으면 TransferUtility에서 검색해 취소(보조 루트)
        if !canceled, let transfer = AWSS3TransferUtility.s3TransferUtility(forKey: transferKey) {
            _ = transfer.getDownloadTasks().continueWith { task in
                if let tasks = task.result as? [AWSS3TransferUtilityDownloadTask] {
                    tasks.filter { $0.key == key }.forEach { $0.cancel() }
                }
                return nil
            }
        }

        // 3) 부분 파일 정리
        if removePartial {
            let localURL = cachesURL(for: normalized)
            try? FileManager.default.removeItem(at: localURL)
        }

        completion?()
    }

    /// 모든 진행 중인 다운로드 취소. removePartial=true면 부분 파일 전부 삭제.
    func cancelAll(removePartial: Bool = true, completion: (() -> Void)? = nil) {
        var files: [String] = []
        syncQ.sync {
            for (fname, task) in downloadTasks {
                task.cancel()
                files.append(fname)
            }
            downloadTasks.removeAll()
        }

        if removePartial {
            files.forEach { try? FileManager.default.removeItem(at: cachesURL(for: $0)) }
        }

        // 보조: TransferUtility에 남은 태스크도 취소
        if let transfer = AWSS3TransferUtility.s3TransferUtility(forKey: transferKey) {
            _ = transfer.getDownloadTasks().continueWith { task in
                if let tasks = task.result as? [AWSS3TransferUtilityDownloadTask] {
                    tasks.forEach { $0.cancel() }
                }
                return nil
            }
        }

        completion?()
    }


    /// HEAD Object 로 단일 파일 사이즈 조회 (bytes). URL 오류 시 PreSigned HEAD로 폴백.
    func headSizeBytes(fileName: String, completion: @escaping (Result<Int64, Error>) -> Void) {
        let s3 = AWSS3.s3(forKey: s3Key)
        let normalized = normalizeFileName(fileName)
        let key = joinKey(prefix: cfg.keyPrefix, fileName: normalized)

        let req = AWSS3HeadObjectRequest()!   // 이 모델은 옵셔널 생성자인 경우가 많음
        req.bucket = cfg.bucket
        req.key = key

        s3.headObject(req).continueWith { task -> Any? in
            if let error = task.error as NSError? {
                if error.domain == NSURLErrorDomain && error.code == -1002 {
                    // unsupported URL → PreSigned HEAD 폴백
                    self.headSizeViaPresigned(fileName: fileName, completion: completion)
                } else {
                    completion(.failure(error))
                }
            } else if let out = task.result, let len = out.contentLength {
                completion(.success(len.int64Value))
            } else {
                completion(.failure(NSError(
                    domain: "NCPDownloader",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "content-length가 없습니다"]
                )))
            }
            return nil
        }
    }

    /// Prefix 아래 객체들의 사이즈를 (파일명 → bytes)로 반환. 대량 합산 시 유용.
    func listObjectSizes(completion: @escaping (Result<[String: Int64], Error>) -> Void) {
        let s3 = AWSS3.s3(forKey: s3Key)
        var sizes: [String: Int64] = [:]

        func fetch(_ token: String?) {
            let req = AWSS3ListObjectsV2Request()!  // 이 모델은 대개 옵셔널 생성자
            req.bucket = cfg.bucket
            let p = cfg.keyPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            req.prefix = p.isEmpty ? nil : p
            req.maxKeys = 1000
            req.continuationToken = token

            s3.listObjectsV2(req).continueWith { task -> Any? in
                if let error = task.error {
                    completion(.failure(error))
                    return nil
                }
                guard let out = task.result, let contents = out.contents else {
                    completion(.success(sizes))
                    return nil
                }

                for obj in contents {
                    guard let key = obj.key, let sizeNum = obj.size else { continue }
                    let fileName = key.split(separator: "/").last.map(String.init) ?? key
                    sizes[fileName] = sizeNum.int64Value
                }

                if out.isTruncated?.boolValue == true, let next = out.nextContinuationToken {
                    fetch(next)
                } else {
                    completion(.success(sizes))
                }
                return nil
            }
        }
        fetch(nil)
    }

    // MARK: - Internals

    private static func sanitizeEndpoint(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // 빈 값/이상치 보정
        if s.isEmpty || s == "/" || s == "https://" || s == "http://" {
            s = "https://kr.object.ncloudstorage.com"
        }

        // 스킴 보장
        let lower = s.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            s = "https://" + s
        }

        // 말단 슬래시 제거
        while s.hasSuffix("/") { s.removeLast() }
        return s
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

    private func cachesURL(for normalized: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent(normalized, isDirectory: false)
    }
    
    /// PreSigned HEAD로 사이즈 조회 (엔드포인트 이슈 등 우회용)
    private func headSizeViaPresigned(fileName: String, completion: @escaping (Result<Int64, Error>) -> Void) {
        // ❗️이 SDK 버전에선 빌더가 non-optional
        let builder = AWSS3PreSignedURLBuilder.s3PreSignedURLBuilder(forKey: presignKey)

        let normalized = normalizeFileName(fileName)
        let key = joinKey(prefix: cfg.keyPrefix, fileName: normalized)

        let req = AWSS3GetPreSignedURLRequest()    // 이 모델은 non-optional 생성자
        req.bucket = cfg.bucket
        req.key = key
        req.httpMethod = AWSHTTPMethod.HEAD        // 타입 명시
        req.expires = Date(timeIntervalSinceNow: 60)

        builder.getPreSignedURL(req).continueWith { task -> Any? in
            // result는 NSURL인 경우가 많음 → URL로 변환
            if let url = task.result as? URL {
                var urlReq = URLRequest(url: url)
                urlReq.httpMethod = "HEAD"
                URLSession.shared.dataTask(with: urlReq) { _, resp, err in
                    if let http = resp as? HTTPURLResponse,
                       let lenStr = (http.allHeaderFields["Content-Length"] as? String) ??
                                    (http.allHeaderFields["content-length"] as? String),
                       let len = Int64(lenStr) {
                        completion(.success(len))
                    } else {
                        completion(.failure(err ?? NSError(
                            domain: "NCPDownloader",
                            code: -5,
                            userInfo: [NSLocalizedDescriptionKey: "PreSigned HEAD Content-Length 없음"]
                        )))
                    }
                }.resume()
            } else if let nsurl = task.result as? NSURL {
                let url = nsurl as URL
                var urlReq = URLRequest(url: url)
                urlReq.httpMethod = "HEAD"
                URLSession.shared.dataTask(with: urlReq) { _, resp, err in
                    if let http = resp as? HTTPURLResponse,
                       let lenStr = (http.allHeaderFields["Content-Length"] as? String) ??
                                    (http.allHeaderFields["content-length"] as? String),
                       let len = Int64(lenStr) {
                        completion(.success(len))
                    } else {
                        completion(.failure(err ?? NSError(
                            domain: "NCPDownloader",
                            code: -5,
                            userInfo: [NSLocalizedDescriptionKey: "PreSigned HEAD Content-Length 없음"]
                        )))
                    }
                }.resume()
            } else {
                completion(.failure(task.error ?? NSError(
                    domain: "NCPDownloader",
                    code: -6,
                    userInfo: [NSLocalizedDescriptionKey: "PreSigned URL 생성 실패"]
                )))
            }
            return nil
        }
    }
}
