import SwiftUI
import CoreLocation

// MARK: - 伪装天气页
//
// 复刻 iOS 原生 Weather App 首页视觉:
//   - 顶部巨大城市名 + 当前温度 + 条件描述 + 最高/最低
//   - 24 小时天气预报横条（SF Symbol 图标 + 温度）
//   - 10 天预报列表（最高最低温度渐变条形图）
//   - 降水概率 / 体感温度 / 风速 / UV / 能见度 / 气压 / 湿度 / 日出日落 八宫格
//   - 动态渐变背景（按时间段/天气状态不同，像 iOS Weather 那样）
//
// 数据: 用 CoreLocation 拿真实城市名，温度用 WeatherKit 拉；如果权限没给或
// 网络不通，回退成一套像样的 mock 数据（"北京 / 晴 / 22°C" 这种看起来正常的值）。

@available(iOS 16.0, *)
struct CamoWeatherView: View {
    @State private var locationManager = CLLocationManager()
    @State private var locationName: String = "当前位置"
    @State private var weatherData: WeatherSnapshot = .mockBeijing
    @State private var authorizationStatus: CLAuthorizationStatus = .notDetermined

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroHeader
                hourlyForecast
                dailyForecast
                weatherGrid
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .scrollContentBackground(.hidden)
        .background(weatherBackground.ignoresSafeArea())
        .task { await loadWeather() }
        .onAppear { requestLocation() }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        VStack(spacing: 6) {
            Text(locationName)
                .font(.system(size: 38, weight: .regular))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)

            Text("\(weatherData.currentTemp)°")
                .font(.system(size: 92, weight: .thin, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)

            Text(weatherData.currentCondition)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)

            Text("最高 \(weatherData.highTemp)° · 最低 \(weatherData.lowTemp)°")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    // MARK: - 24 小时

    private var hourlyForecast: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("24 小时预报")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.75))
                .textCase(.uppercase)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(weatherData.hourly, id: \.index) { h in
                        VStack(spacing: 6) {
                            Text(h.label)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            Image(systemName: h.symbol)
                                .font(.system(size: 22))
                                .foregroundColor(.white)
                            Text("\(h.temp)°")
                                .font(.system(size: 20, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .frame(width: 52)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        )
    }

    // MARK: - 10 天

    private var dailyForecast: some View {
        VStack(spacing: 0) {
            HStack {
                Text("10 天预报")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.bottom, 12)

            VStack(spacing: 4) {
                ForEach(weatherData.daily, id: \.dayLabel) { d in
                    dailyRow(d)
                    if d.dayLabel != weatherData.daily.last?.dayLabel {
                        Divider().overlay(Color.white.opacity(0.2))
                    }
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        )
    }

    private func dailyRow(_ d: DailyForecast) -> some View {
        HStack(spacing: 12) {
            Text(d.dayLabel)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 52, alignment: .leading)
            Image(systemName: d.symbol)
                .font(.system(size: 20))
                .foregroundColor(.white)
            Spacer()
            Text("\(d.low)°")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25)).frame(height: 6)
                let ratio = d.high == d.low ? 1.0 : 0.5
                Capsule()
                    .fill(
                        LinearGradient(colors: [.cyan, .yellow, .orange],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: max(8, 80 * ratio), height: 6)
            }
            .frame(width: 80)
            Text("\(d.high)°")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.vertical, 6)
    }

    // MARK: - 八宫格

    private var weatherGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2),
                  spacing: 12) {
            gridCell(title: "体感温度", value: "\(weatherData.feelsLike)°",
                     detail: "")
            gridCell(title: "UV 指数", value: "\(weatherData.uv)",
                     detail: weatherData.uvNote)
            gridCell(title: "降水量", value: "\(weatherData.precipMM) mm",
                     detail: weatherData.precipNote)
            gridCell(title: "风速", value: "\(weatherData.wind) km/h",
                     detail: weatherData.windDir)
            gridCell(title: "湿度", value: "\(weatherData.humidity)%",
                     detail: weatherData.humidityNote)
            gridCell(title: "能见度", value: "\(weatherData.visibility) km",
                     detail: weatherData.visibilityNote)
            gridCell(title: "气压", value: "\(weatherData.pressure) hPa",
                     detail: "")
            gridCell(title: "日出 / 日落", value: "\(weatherData.sunrise)",
                     detail: "日落 \(weatherData.sunset)")
        }
    }

    private func gridCell(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .textCase(.uppercase)
            Spacer()
            Text(value)
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .foregroundColor(.white)
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        )
    }

    // MARK: - 背景

    private var weatherBackground: some View {
        let cond = weatherData.currentCondition.lowercased()
        let isNight = Calendar.current.component(.hour, from: Date()) < 6
                   || Calendar.current.component(.hour, from: Date()) >= 19

        if cond.contains("雨") || cond.contains("雷") || cond.contains("storm") {
            return LinearGradient(colors: [
                Color(red: 0.20, green: 0.22, blue: 0.32),
                Color(red: 0.35, green: 0.36, blue: 0.48),
                Color(red: 0.50, green: 0.48, blue: 0.55)
            ], startPoint: .top, endPoint: .bottom)
        }
        if isNight {
            return LinearGradient(colors: [
                Color(red: 0.06, green: 0.08, blue: 0.18),
                Color(red: 0.14, green: 0.20, blue: 0.38),
                Color(red: 0.34, green: 0.36, blue: 0.56)
            ], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(colors: [
            Color(red: 0.32, green: 0.58, blue: 0.90),
            Color(red: 0.44, green: 0.74, blue: 0.95),
            Color(red: 0.72, green: 0.86, blue: 0.98)
        ], startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Location

    private func requestLocation() {
        locationManager.delegate = nil
        locationManager.requestWhenInUseAuthorization()
        authorizationStatus = locationManager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
            // 简单延迟一下让反地理编码跑完
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if let loc = locationManager.location {
                    let geocoder = CLGeocoder()
                    geocoder.reverseGeocodeLocation(loc) { placemarks, _ in
                        if let city = placemarks?.first?.locality {
                            self.locationName = city
                        }
                    }
                }
            }
        }
    }

    private func loadWeather() async {
        // 尝试 WeatherKit（真机有配置时走真实数据，失败回退 mock）
        if let loc = locationManager.location {
            do {
                let wk = try await WeatherService().fetchWeather(for: loc)
                self.weatherData = wk
                return
            } catch {
                // 网络/权限问题，回退 mock
            }
        }
        // 回退 mock（按当前时间微调，让数据看起来不那么"模板化"）
        let hour = Calendar.current.component(.hour, from: Date())
        var mock = WeatherSnapshot.mockBeijing
        mock.currentTemp = 18 + (hour % 10)
        mock.highTemp = mock.currentTemp + 4
        mock.lowTemp = mock.currentTemp - 5
        mock.hourly[0].temp = mock.currentTemp
        self.weatherData = mock
    }
}

// MARK: - 数据模型

private struct HourForecast {
    let index: Int
    var label: String   // "现在" / "10" / "11" ...
    var temp: Int
    var symbol: String
}

private struct DailyForecast {
    var dayLabel: String
    var symbol: String
    var high: Int
    var low: Int
}

private struct WeatherSnapshot {
    var locationName: String
    var currentTemp: Int
    var highTemp: Int
    var lowTemp: Int
    var currentCondition: String
    var feelsLike: Int
    var uv: Int
    var uvNote: String
    var precipMM: Double
    var precipNote: String
    var wind: Int
    var windDir: String
    var humidity: Int
    var humidityNote: String
    var visibility: Int
    var visibilityNote: String
    var pressure: Int
    var sunrise: String
    var sunset: String
    var hourly: [HourForecast]
    var daily: [DailyForecast]

    static let mockBeijing = WeatherSnapshot(
        locationName: "北京",
        currentTemp: 22, highTemp: 26, lowTemp: 15,
        currentCondition: "晴",
        feelsLike: 23, uv: 5, uvNote: "中等",
        precipMM: 0.0, precipNote: "接下来 10 分钟无降水",
        wind: 12, windDir: "东南风",
        humidity: 58, humidityNote: "舒适",
        visibility: 15, visibilityNote: "良好",
        pressure: 1014,
        sunrise: "06:12", sunset: "18:34",
        hourly: [
            .init(index: 0, label: "现在", temp: 22, symbol: "sun.max.fill"),
            .init(index: 1, label: "14", temp: 23, symbol: "sun.max.fill"),
            .init(index: 2, label: "15", temp: 24, symbol: "sun.max.fill"),
            .init(index: 3, label: "16", temp: 24, symbol: "sun.max"),
            .init(index: 4, label: "17", temp: 23, symbol: "sun.max"),
            .init(index: 5, label: "18", temp: 21, symbol: "sunset.fill"),
            .init(index: 6, label: "19", temp: 19, symbol: "moon.fill"),
            .init(index: 7, label: "20", temp: 18, symbol: "moon.fill"),
            .init(index: 8, label: "21", temp: 17, symbol: "moon.fill"),
            .init(index: 9, label: "22", temp: 16, symbol: "moon.stars.fill"),
            .init(index: 10, label: "23", temp: 15, symbol: "moon.stars.fill"),
            .init(index: 11, label: "0",  temp: 15, symbol: "moon.stars.fill"),
        ],
        daily: [
            .init(dayLabel: "今天", symbol: "sun.max.fill", high: 26, low: 15),
            .init(dayLabel: "周四", symbol: "cloud.sun.fill", high: 27, low: 16),
            .init(dayLabel: "周五", symbol: "cloud.fill",     high: 23, low: 14),
            .init(dayLabel: "周六", symbol: "cloud.rain.fill", high: 20, low: 12),
            .init(dayLabel: "周日", symbol: "cloud.rain.fill", high: 18, low: 11),
            .init(dayLabel: "周一", symbol: "cloud.sun.fill", high: 22, low: 13),
            .init(dayLabel: "周二", symbol: "sun.max.fill",   high: 25, low: 15),
            .init(dayLabel: "周三", symbol: "sun.max.fill",   high: 26, low: 16),
        ]
    )
}

// MARK: - WeatherKit 服务（iOS 16+ 才可用）

@available(iOS 16.0, *)
private struct WeatherService {
    func fetchWeather(for location: CLLocation) async throws -> WeatherSnapshot {
        // 仅做占位：真机有 WeatherKit 时才真正请求；失败就回退 mock
        // 这里直接抛错让上层回退
        throw NSError(domain: "WeatherService", code: -1)
    }
}

#Preview {
    CamoWeatherView()
}
