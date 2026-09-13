//
//  Item.swift
//  Monaka
//
//  Created by satoshikobayashi on 2026/09/13.
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
