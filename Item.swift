//
//  Item.swift
//  BDinfoScan
//
//  Created by nan on 2026/3/18.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
