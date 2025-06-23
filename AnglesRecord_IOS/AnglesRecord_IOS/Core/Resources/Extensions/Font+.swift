//
//  Font+.swift
//  AnglesRecord_IOS
//
//  Created by 광로 on 6/23/25.
//
import SwiftUI

extension Font {
    
    enum SFPro {
        
        enum Regular {
            static let s16 = Font.custom("SFProText-Regular", size: 16)
            static let s14 = Font.custom("SFProText-Regular", size: 14)
            static let s12 = Font.custom("SFProText-Regular", size: 12)
        }
        enum SemiBold {
            static let s16 = Font.custom("SFProText-Semibold", size: 16)
            static let s14 = Font.custom("SFProText-Semibold", size: 14)
            static let s12 = Font.custom("SFProText-Semibold", size: 12)
            static let s10 = Font.custom("SFProText-Semibold", size: 10)
            static let s11 = Font.custom("SFProText-Semibold", size: 11)
            static let s24 = Font.custom("SFProText-Semibold", size: 24)
        }
        
        enum Medium {
            static let s17 = Font.custom("SFProText-Medium", size: 17)
            static let s14 = Font.custom("SFProText-Medium", size: 14)
            static let s12 = Font.custom("SFProText-Medium", size: 12)
            static let s10 = Font.custom("SFProText-Medium", size: 10)
            static let s20 = Font.custom("SFProText-Medium", size: 20)
            static let s16 = Font.custom("SFProText-Medium", size: 16)
            
        }
    }
    
}
