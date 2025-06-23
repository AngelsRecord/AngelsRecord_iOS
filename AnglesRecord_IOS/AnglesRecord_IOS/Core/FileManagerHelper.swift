//
//  FileManagerHelper.swift
//  AnglesRecord_IOS
//
//  Created by 성현 on 6/24/25.
//

import Foundation

func localFileURL(for fileName: String) -> URL {
    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return documentsPath.appendingPathComponent(fileName)
}

func fileExistsLocally(fileName: String) -> Bool {
    let path = localFileURL(for: fileName).path
    return FileManager.default.fileExists(atPath: path)
}
