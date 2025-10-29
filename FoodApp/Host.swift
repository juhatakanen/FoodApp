//
//  Host.swift
//  FoodApp
//
//  Created by Juha Takanen on 29.10.2025.
//

import Foundation

enum Host: String, Hashable {
    case semma
    case compass
    
    // Pure computed values – make available from any actor
    nonisolated var dayMenuBase: String {
        switch self {
        case .semma: return "https://www.semma.fi/menuapi/day-menus"
        case .compass: return "https://www.compass-group.fi/menuapi/day-menus"
        }
    }
    
    nonisolated var recipeBase: String {
        switch self {
        case .semma: return "https://www.semma.fi/menuapi/recipes"
        case .compass: return "https://www.compass-group.fi/menuapi/recipes"
        }
    }
}

struct Restaurant: Hashable {
    let name: String
    let costCenter: String   // keep as String to preserve leading zeros
    let host: Host
}
