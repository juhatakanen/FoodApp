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

enum Host: String, Hashable {
    case semma
    case compass
    
    var dayMenuBase: String {
        switch self {
        case .semma: return "https://www.semma.fi/menuapi/day-menus"
        case .compass: return "https://www.compass-group.fi/menuapi/day-menus"
        }
    }
    
    var recipeBase: String {
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

struct ContentView: View {
    @State private var meals = [DisplayMeal]()
    @State private var nutrientStats: [CompositeKey: NutrientStats] = [:]
    @State private var sortedMeals = [DisplayMeal]()

    var body: some View {
        NavigationStack {
            List(sortedMeals) { meal in
                NavigationLink(destination: MealDetailView(recipeId: meal.recipeId, mealName: meal.name, host: meal.host)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meal.name)
                            .font(.headline)
                        Text(meal.restaurantName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let stats = nutrientStats[CompositeKey(recipeId: meal.recipeId, host: meal.host)], stats.kcalPerProtein.isFinite {
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
        // Date string you want to fetch
        let dateStr = "2025-10-29"
        let restaurants: [Restaurant] = [
            .init(name: "Rentukka", costCenter: "1416", host: .semma),
            .init(name: "Piato",    costCenter: "1408", host: .semma),
            .init(name: "Lozzi",    costCenter: "1401", host: .semma),
            .init(name: "Uno",      costCenter: "1414", host: .semma),
            .init(name: "Syke",     costCenter: "1405", host: .semma),
            .init(name: "Ylistö",   costCenter: "1403", host: .semma),
            .init(name: "Taide",    costCenter: "0301", host: .compass),
            .init(name: "Fiilu",    costCenter: "3364", host: .compass),
        ]
        
        await withTaskGroup(of: [DisplayMeal].self) { group in
            for r in restaurants {
                group.addTask {
                    var components = URLComponents(string: r.host.dayMenuBase)!
                    components.queryItems = [
                        URLQueryItem(name: "costCenter", value: r.costCenter),
                        URLQueryItem(name: "date", value: dateStr),
                        URLQueryItem(name: "language", value: "fi"),
                    ]
                    guard let url = components.url else { return [] }
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        if let decoded = try? JSONDecoder().decode(DayMenu.self, from: data) {
                            let meals = decoded.menuPackages.flatMap { $0.meals }
                            let displayMeals = meals.map { m in
                                DisplayMeal(
                                    id: "\(m.recipeId)-\(m.name)-\(r.host.rawValue)",
                                    name: m.name,
                                    recipeId: m.recipeId,
                                    diets: m.diets,
                                    iconUrl: m.iconUrl,
                                    restaurantName: r.name,
                                    host: r.host
                                )
                            }
                            return displayMeals
                        }
                    } catch {
                        print("Day menu fetch failed for \(r.name):", error)
                    }
                    return []
                }
            }
            var combined: [DisplayMeal] = []
            for await chunk in group {
                combined.append(contentsOf: chunk)
            }
            await MainActor.run {
                self.meals = combined
            }
        }
        // Fetch nutrient stats then compute sorted list
        await fetchNutrientStats(for: meals)
        await MainActor.run {
            computeSortedMeals()
        }
    }
    
    private func fetchNutrientStats(for meals: [DisplayMeal]) async {
        await withTaskGroup(of: (CompositeKey, NutrientStats?)?.self) { group in
            for meal in meals {
                let recipeId = meal.recipeId
                guard recipeId != 0 else { continue }
                let key = CompositeKey(recipeId: recipeId, host: meal.host)
                group.addTask {
                    guard let url = URL(string: "\(meal.host.recipeBase)/\(recipeId)?language=fi") else {
                        return (key, nil)
                    }
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        let detail = try JSONDecoder().decode(RecipeDetail.self, from: data)
                        let kcal = detail.nutritionalValues.first(where: { $0.name == "EnergyKcal" })?.amount
                        let protein = detail.nutritionalValues.first(where: { $0.name == "Protein" })?.amount
                        if let kcal, let protein {
                            return (key, NutrientStats(protein: protein, kcal: kcal))
                        } else {
                            return (key, nil)
                        }
                    } catch {
                        print("Failed to fetch stats for \(recipeId) at \(meal.host):", error)
                        return (key, nil)
                    }
                }
            }
            var newStats: [CompositeKey: NutrientStats] = [:]
            for await result in group {
                if let (k, stat) = result, let stat {
                    newStats[k] = stat
                }
            }
            await MainActor.run {
                self.nutrientStats = newStats
            }
        }
    }
    
    private func computeSortedMeals() {
        let (withStats, withoutStats) = meals.partitioned { meal in
            let key = CompositeKey(recipeId: meal.recipeId, host: meal.host)
            if let stats = nutrientStats[key] {
                return stats.kcalPerProtein.isFinite
            }
            return false
        }
        let sortedWithStats = withStats.sorted {
            let ka = CompositeKey(recipeId: $0.recipeId, host: $0.host)
            let kb = CompositeKey(recipeId: $1.recipeId, host: $1.host)
            guard let a = nutrientStats[ka], let b = nutrientStats[kb] else { return false }
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
    let host: Host
    
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
        guard let url = URL(string: "\(host.recipeBase)/\(recipeId)?language=fi") else {
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
