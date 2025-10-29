//
//  Models.swift
//  FoodApp
//
//  Created by Juha Takanen on 29.10.2025.
//

import Foundation

// MARK: - Semma/Compass day menu JSON
struct DayMenu: Codable {
    let dayOfWeek: String
    let date: String
    let menuPackages: [MenuPackage]
    let html: String?
    let isManualMenu: Bool
}

struct MenuPackage: Codable {
    let sortOrder: Int
    let name: String
    let price: String?
    let meals: [Meal]
}

struct Meal: Codable, Identifiable {
    let name: String
    let recipeId: Int
    let diets: [String]
    let iconUrl: String
    
    var id: String { "\(recipeId)-\(name)" }
}

// MARK: - Recipe detail JSON
struct RecipeDetail: Codable {
    let recipeId: Int
    let name: String
    let ingredientsCleaned: String
    let lastModified: String
    let nutritionalValues: [NutritionalValue]
    let kgCO2ePer100g: Double?
    let diets: String?
}

struct NutritionalValue: Codable, Identifiable {
    var id: String { name }
    let name: String
    let amount: Double
    let unit: String
}

// MARK: - View models & helpers
struct DisplayMeal: Identifiable, Hashable {
    let id: String           // recipeId-name-host to ensure uniqueness
    let name: String
    let recipeId: Int
    let diets: [String]
    let iconUrl: String
    let restaurantName: String
    let host: Host
}

struct NutrientStats {
    let protein: Double
    let kcal: Double
    var kcalPerProtein: Double { protein > 0 ? kcal / protein : .infinity }
}

struct CompositeKey: Hashable {
    let recipeId: Int
    let host: Host
}

// MARK: - Small utilities
extension Array {
    func partitioned(by belongsInFirstPartition: (Element) -> Bool) -> ([Element], [Element]) {
        var first: [Element] = []
        var second: [Element] = []
        for element in self {
            if belongsInFirstPartition(element) {
                first.append(element)
            } else {
                second.append(element)
            }
        }
        return (first, second)
    }
}
