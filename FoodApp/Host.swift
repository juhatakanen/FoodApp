//
//  Host.swift
//  FoodApp
//
//  Created by Juha Takanen on 29.10.2025.
//

import Foundation
import SwiftUI

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

extension Restaurant {
    var color: Color {
        switch name {
        case "Rentukka": return .green
        case "Taide": return .yellow.opacity(0.5)
        case "Lozzi": return .orange
        case "Ilokivi": return .yellow.opacity(0.8)
        case "Uno": return Color(red: 0.8, green: 1.0, blue: 0.8) // yellow with green tint
        case "Syke": return Color(red: 1.0, green: 1.0, blue: 0.6) // yellow with blue hint
        case "Ylistö": return .cyan
        case "Piato": return .blue
        case "Fiilu": return .red
        default: return .gray
        }
    }
}
