//
//  ContentView.swift
//  FoodApp
//
//  Created by Juha Takanen on 29.10.2025.
//

import SwiftUI

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

struct NutrientStats {
    let protein: Double
    let kcal: Double
    var kcalPerProtein: Double { protein > 0 ? kcal / protein : .infinity }
}

struct ContentView: View {
    @State private var meals = [Meal]()
    @State private var nutrientStats: [Int: NutrientStats] = [:] // key: recipeId
    @State private var sortedMeals = [Meal]()

    var body: some View {
        NavigationStack {
            List(sortedMeals) { meal in
                NavigationLink(destination: MealDetailView(recipeId: meal.recipeId, mealName: meal.name)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meal.name)
                            .font(.headline)
                        if let stats = nutrientStats[meal.recipeId], stats.kcalPerProtein.isFinite {
                            HStack(spacing: 12) {
                                Text("Protein: \(formatNumber(stats.protein)) g")
                                Text("Calories: \(formatNumber(stats.kcal)) kcal")
                                Text("kcal/g protein: \(formatNumber(stats.kcalPerProtein))")
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        } else {
                            Text("Nutrition unavailable")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .navigationTitle("Semma Menu")
        }
        .task {
            await loadData()
        }
    }
    func loadData() async {
        guard let url = URL(string: "https://www.semma.fi/menuapi/day-menus?costCenter=1408&date=2025-10-29&language=fi") else {
            print("Invalid URL")
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            if let decodedMenu = try? JSONDecoder().decode(DayMenu.self, from: data) {
                let flatMeals = decodedMenu.menuPackages.flatMap { $0.meals }
                await MainActor.run {
                    meals = flatMeals
                }
                // Fetch nutrient stats for each meal (concurrently), then compute sorted order
                await fetchNutrientStats(for: flatMeals)
                await MainActor.run {
                    computeSortedMeals()
                }
            }
        } catch {
            print("Decoding or network error:", error)
        }
    }
    
    private func fetchNutrientStats(for meals: [Meal]) async {
        await withTaskGroup(of: (Int, NutrientStats?)?.self) { group in
            for meal in meals {
                let recipeId = meal.recipeId
                guard recipeId != 0 else { continue }
                group.addTask {
                    guard let url = URL(string: "https://www.semma.fi/menuapi/recipes/\(recipeId)?language=fi") else {
                        return (recipeId, nil)
                    }
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        let detail = try JSONDecoder().decode(RecipeDetail.self, from: data)
                        // Extract kcal and protein from nutritionalValues
                        let kcal = detail.nutritionalValues.first(where: { $0.name == "EnergyKcal" })?.amount
                        let protein = detail.nutritionalValues.first(where: { $0.name == "Protein" })?.amount
                        if let kcal, let protein {
                            return (recipeId, NutrientStats(protein: protein, kcal: kcal))
                        } else {
                            return (recipeId, nil)
                        }
                    } catch {
                        print("Failed to fetch stats for \(recipeId):", error)
                        return (recipeId, nil)
                    }
                }
            }
            var newStats: [Int: NutrientStats] = [:]
            for await result in group {
                if let (rid, stat) = result, let stat {
                    newStats[rid] = stat
                }
            }
            await MainActor.run {
                self.nutrientStats = newStats
            }
        }
    }
    
    private func computeSortedMeals() {
        // Meals with valid stats first, sorted by kcal/protein ascending; others at bottom
        let (withStats, withoutStats) = meals.partitioned { meal in
            if let stats = nutrientStats[meal.recipeId] {
                return stats.kcalPerProtein.isFinite
            }
            return false
        }
        let sortedWithStats = withStats.sorted {
            guard let a = nutrientStats[$0.recipeId], let b = nutrientStats[$1.recipeId] else { return false }
            return a.kcalPerProtein < b.kcalPerProtein
        }
        self.sortedMeals = sortedWithStats + withoutStats
    }
    
    private func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.decimalSeparator = Locale.current.decimalSeparator
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

#Preview {
    ContentView()
}

// Models for recipe detail and detail view
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

struct MealDetailView: View {
    let recipeId: Int
    let mealName: String
    
    @State private var detail: RecipeDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Ladataan…")
            } else if let detail {
                List {
                    Section("Ravitsemus (per 100 g)") {
                        ForEach(detail.nutritionalValues) { nv in
                            HStack {
                                Text(prettyLabel(for: nv.name))
                                Spacer()
                                Text("\(formatNumber(nv.amount)) \(nv.unit)")
                                    .monospacedDigit()
                            }
                        }
                    }
                    if let diets = detail.diets, !diets.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Section("Erityisruokavaliot") {
                            Text(diets)
                        }
                    }
                    if let co2 = detail.kgCO2ePer100g {
                        Section("Ilmastovaikutus") {
                            Text("\(formatNumber(co2)) kgCO₂e / 100 g")
                        }
                    }
                    Section("Ainesosat") {
                        Text(detail.ingredientsCleaned)
                            .font(.footnote)
                    }
                }
                .listStyle(.insetGrouped)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Text("Virhe")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                Text("Ei tietoja tälle annokselle.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(mealName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDetail()
        }
    }
    
    private func loadDetail() async {
        guard recipeId != 0 else {
            // Some items are generic and have recipeId 0
            return
        }
        guard let url = URL(string: "https://www.semma.fi/menuapi/recipes/\(recipeId)?language=fi") else {
            errorMessage = "Virheellinen osoite."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(RecipeDetail.self, from: data)
            await MainActor.run {
                self.detail = decoded
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Tietojen hakeminen epäonnistui. \(error.localizedDescription)"
            }
            print("Recipe detail fetch error:", error)
        }
    }
    
    private func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.decimalSeparator = Locale.current.decimalSeparator
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    private func prettyLabel(for code: String) -> String {
        switch code {
        case "EnergyKcal": return "Energia"
        case "EnergyKj": return "Energia (kJ)"
        case "Protein": return "Proteiini"
        case "Carbohydrates": return "Hiilihydraatit"
        case "Sugar": return "Sokeri"
        case "Fat": return "Rasva"
        case "FatSaturated": return "Tyydyttynyt rasva"
        case "Salt": return "Suola"
        case "Fiber": return "Ravintokuitu"
        default: return code
        }
    }
}
