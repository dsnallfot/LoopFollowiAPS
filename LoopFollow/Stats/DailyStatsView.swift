// LoopFollow
// DailyStatsView.swift

import SwiftUI
import UIKit
import WebKit

@available(iOS 16.0, *)
struct DailyStatsView: View {
    @ObservedObject var viewModel: DailyStatsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var exportURL: URL?
    @State private var showingTitrSummary: Bool = true
    @State private var selectedDateForReport: Date?
    @State private var showNightscoutAlert: Bool = false
    @State private var showNightscoutReport: Bool = false

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    // Kolumnbredder för raka marginaler
    private let dateWidth: CGFloat = 66
        private let carbsWidth: CGFloat = 36
        private let insulinWidth: CGFloat = 36
        private let meanWidth: CGFloat = 36
        private let lowWidth: CGFloat = 36
        private let titrWidth: CGFloat = 36
        private let tirWidth: CGFloat = 36
        private let stdWidth: CGFloat = 36
        private let profileWidth: CGFloat = 36
        private let emptyWidth: CGFloat = 10

        private let columnSpacing: CGFloat = 1

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.rows.isEmpty {
                    ProgressView("Beräknar daglig statistik…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        summarySection
                            .padding(.horizontal, 10)
                            .padding(.top, 8)

                        ScrollView(.horizontal) {
                            VStack(alignment: .leading, spacing: 0) {
                                headerRow
                                    .padding(.vertical, 6)
                                Divider()

                                ScrollView(.vertical) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(Array(viewModel.rowsWithSufficientGlucose.filter { $0.tightRangePercent != nil }.enumerated()), id: \.element.id) { index, row in
                                            HStack(spacing: columnSpacing) {
                                                Text(dateFormatter.string(from: row.date))
                                                    .frame(width: dateWidth, alignment: .leading)
                                                    .font(.system(size: 10).monospacedDigit())

                                                numberCell(row.totalCarbs, width: carbsWidth, decimals: 0)
                                                numberCell(row.insulinTDD, width: insulinWidth)
                                                meanCell(row.meanGlucoseMmol)
                                                lowCell(row.lowPercent)
                                                titrCell(row.tightRangePercent)
                                                tirCell(row.timeInRangePercent)
                                                stdDevCell(stdDev: row.stdDevMmol, mean: row.meanGlucoseMmol)
                                                numberCell(row.profileBasal, width: profileWidth)
                                                emptyCell(row.emptyInfo, width: emptyWidth)
                                            }
                                            .padding(.vertical, 4)
                                            .background(index % 2 == 0 ? Color(.systemGray5.withAlphaComponent(0.6)) : Color.clear)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                selectedDateForReport = row.date
                                                showNightscoutAlert = true
                                            }
                                            Divider()
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 12)
                            //.padding(.bottom, 12)
                        }
                    }
                }
            }
            .navigationTitle("Daglig statistik")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        if let url = viewModel.writeCSVToDisk() {
                            exportURL = url
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Klar") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.loadDailyStats()
            }
            .sheet(
                isPresented: Binding(
                    get: { exportURL != nil },
                    set: { isPresented in
                        if !isPresented {
                            exportURL = nil
                        }
                    }
                )
            ) {
                if let url = exportURL {
                    ActivityView(activityItems: [url])
                }
            }
            .fullScreenCover(isPresented: $showNightscoutReport) {
                if let date = selectedDateForReport {
                    NightscoutDayReportView(date: date)
                }
            }
            .alert("Fel", isPresented: .constant(viewModel.errorMessage != nil), actions: {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            }, message: {
                Text(viewModel.errorMessage ?? "")
            })
            .overlay(
                Color.clear
                    .allowsHitTesting(false)
                    .alert(
                        "Visa dagsrapport i Nightscout?",
                        isPresented: $showNightscoutAlert
                    ) {
                        Button("Avbryt", role: .cancel) { }
                        Button("Fortsätt") {
                            showNightscoutReport = true
                        }
                    } message: {
                        if let date = selectedDateForReport {
                            Text("Datum: \(dateFormatter.string(from: date))")
                        } else {
                            Text("Visa daglig Nightscout-rapport.")
                        }
                    }
            )
        }
    }

    // MARK: - Subviews

    private var summarySection: some View {
        let daysInScope = viewModel.numberOfDaysInScope
        let daysMeetingTitr = viewModel.numberOfDaysMeetingTitrTarget
        let daysMeetingTir = viewModel.numberOfDaysMeetingTirTarget
        let titrThresholdPercentString = String(format: "%.0f%%", viewModel.titrTargetThreshold * 100)
        let tirThresholdPercentString = String(format: "%.0f%%", viewModel.tirTargetThreshold * 100)
        let daysInScopeString = "\(daysInScope)"
        let daysMeetingTitrString = "\(daysMeetingTitr)"
        let daysMeetingTirString = "\(daysMeetingTir)"

        return Group {
            if daysInScope > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Group {
                        VStack(alignment: .leading, spacing: 4) {
                            // Rad 1: “Du nådde ditt mål på XX% tid i ...”
                            HStack(spacing: 0) {
                                Text("Du nådde ditt mål på ")
                                Text(showingTitrSummary ? titrThresholdPercentString : tirThresholdPercentString)
                                    .fontWeight(.bold)
                                    .foregroundColor(Color.green.opacity(0.8))
                                Text(showingTitrSummary ? " tid i tight målområde" : " tid i målområde ")
                            }

                            // Rad 2: intervallet i grått
                            HStack(spacing: 0) {
                            Text(showingTitrSummary ? "(3.9–7.8 mmol/L) " : "(3.9–10.0 mmol/L) ")
                                .foregroundColor(.secondary)
                                Text("under ")
                                Text(showingTitrSummary ? daysMeetingTitrString : daysMeetingTirString)
                                    .fontWeight(.bold)
                                Text(" av de senaste ")
                                Text(daysInScopeString)
                                    .fontWeight(.bold)
                                Text(" dagarna.")
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)

                    if showingTitrSummary {
                        titrStreakBar
                    } else {
                        tirStreakBar
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingTitrSummary.toggle()
                    }
                }
            } else {
                Text("Ingen daglig statistik att visa ännu.")
            }
        }
        .font(.system(size: 14))
        .multilineTextAlignment(.leading)
    }

    /// Visar en enkel streak/gap-rad där varje dag i perioden representeras av en stapel.
    /// Grön = dag når TITR-målet, transparent = dag under målet.
    /// Endast dagar där vi har TITR-data (tightRangePercent != nil) ritas ut.
    private var titrStreakBar: some View {
        // Sortera dagar i kronologisk ordning (äldst till nyast) för vänster-till-höger-läsning
        // och filtrera bort dagar utan TITR-data.
        let filteredRows = viewModel.rowsWithSufficientGlucose
            .sorted { $0.date < $1.date }
            .filter { $0.tightRangePercent != nil }

        let barHeight: CGFloat = 15
        let barSpacing: CGFloat = 1

        return GeometryReader { geometry in
            let count = max(filteredRows.count, 1)
            let totalSpacing = barSpacing * CGFloat(max(count - 1, 0))
            let barWidth = max((geometry.size.width - totalSpacing) / CGFloat(count), 2)

            HStack(spacing: barSpacing) {
                ForEach(Array(filteredRows.enumerated()), id: \.offset) { _, row in
                    let meetsTarget = ((row.tightRangePercent ?? 0) / 100.0) >= viewModel.titrTargetThreshold

                    Rectangle()
                        .fill(meetsTarget ? Color.green.opacity(0.8) : Color.red.opacity(0.7))
                        .frame(width: barWidth, height: barHeight)
                        .overlay(
                            Rectangle()
                                .stroke(Color.green.opacity(0.2), lineWidth: 0.5)
                        )
                }
            }
        }
        .frame(height: barHeight)
    }
    
    private var tirStreakBar: some View {
        // Sortera dagar i kronologisk ordning (äldst till nyast) för vänster-till-höger-läsning
        // och filtrera bort dagar utan TITR-data.
        let filteredRows = viewModel.rowsWithSufficientGlucose
            .sorted { $0.date < $1.date }
            .filter { $0.timeInRangePercent != nil }

        let barHeight: CGFloat = 15
        let barSpacing: CGFloat = 1

        return GeometryReader { geometry in
            let count = max(filteredRows.count, 1)
            let totalSpacing = barSpacing * CGFloat(max(count - 1, 0))
            let barWidth = max((geometry.size.width - totalSpacing) / CGFloat(count), 2)

            HStack(spacing: barSpacing) {
                ForEach(Array(filteredRows.enumerated()), id: \.offset) { _, row in
                    let meetsTarget = ((row.timeInRangePercent ?? 0) / 100.0) >= viewModel.tirTargetThreshold

                    Rectangle()
                        .fill(meetsTarget ? Color.green.opacity(0.8) : Color.red.opacity(0.7))
                        .frame(width: barWidth, height: barHeight)
                        .overlay(
                            Rectangle()
                                .stroke(Color.green.opacity(0.2), lineWidth: 0.5)
                        )
                }
            }
        }
        .frame(height: barHeight)
    }

    private var headerRow: some View {
        HStack(spacing: columnSpacing) {
            Text("Datum")
                .frame(width: dateWidth, alignment: .leading)
                .font(.system(size: 10, weight: .semibold))

            Text("Kolh")
                .frame(width: carbsWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))

            Text("TDD")
                .frame(width: insulinWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))

            Text("Medel")
                .frame(width: meanWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))

            Text("Låg")
                .frame(width: lowWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))

            Text("TITR")
                .frame(width: titrWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))
            
            Text("TIR")
                .frame(width: tirWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))

            Text("Std.av")
                .frame(width: stdWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))

            Text("Basal")
                .frame(width: profileWidth, alignment: .trailing)
                .font(.system(size: 10, weight: .semibold))
        }
    }

    private func numberCell(
        _ value: Double?,
        width: CGFloat,
        decimals: Int = 1,
        foregroundColor: Color? = nil
    ) -> some View {
        Group {
            if let value = value {
                Text(String(format: "%.\(decimals)f", value))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(foregroundColor ?? .primary)
            } else {
                Text("—")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: width, alignment: .trailing)
    }
    
    private func emptyCell(
        _ value: String?,
        width: CGFloat,
        decimals: Int = 0,
        foregroundColor: Color? = nil
    ) -> some View {
        Group {
            if value != nil {
                Text("")
            } else {
                Text("")
            }
        }
        .frame(width: width, alignment: .trailing)
    }

    private func lowCell(_ value: Double?) -> some View {
        let color: Color
        if let value = value {
            let fraction = value / 100.0
            if fraction <= viewModel.lowGlucoseGreatThreshold {
                color = .green
            } else if fraction <= viewModel.lowGlucoseOKThreshold {
                color = .orange
            } else {
                color = .red
            }
        } else {
            color = .secondary
        }
        return numberCell(value, width: lowWidth, decimals: 1, foregroundColor: color)
    }

    private func titrCell(_ value: Double?) -> some View {
        let color: Color
        //if showingTitrSummary {
            if let value = value {
                let fraction = value / 100.0
                color = fraction >= viewModel.titrTargetThreshold ? .green : .red
            } else {
                color = .secondary
            }
        //} else {
        //    color = .secondary
        //}
        return numberCell(value, width: titrWidth, decimals: 0, foregroundColor: color)
    }
    
    private func tirCell(_ value: Double?) -> some View {
        let color: Color
        //if !showingTitrSummary {
        if let value = value {
            let fraction = value / 100.0
            color = fraction >= viewModel.tirTargetThreshold ? .green : .red
        } else {
            color = .secondary
        }
        //} else {
        //    color = .secondary
        //}
        return numberCell(value, width: tirWidth, decimals: 0, foregroundColor: color)
    }

    private func meanCell(_ value: Double?) -> some View {
        let color: Color
        if let value = value {
            if value <= viewModel.bgAverageGreatThreshold {
                color = .green
            } else if value <= viewModel.bgAverageOKThreshold {
                color = .orange
            } else {
                color = .red
            }
        } else {
            color = .secondary
        }
        return numberCell(value, width: meanWidth, decimals: 1, foregroundColor: color)
    }

    private func stdDevCell(stdDev: Double?, mean: Double?) -> some View {
        let color: Color
        if let stdDev = stdDev, stdDev > 0 {
            if stdDev <= viewModel.stdDevGreatThreshold {
                color = .green
            } else if stdDev <= viewModel.stdDevOkThreshold {
                color = .orange
            } else {
                color = .red
            }
        } else {
            color = .secondary
        }
        return numberCell(stdDev, width: stdWidth, decimals: 1, foregroundColor: color)
    }
}

// MARK: - UIActivityViewController bridge

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

@available(iOS 16.0, *)
struct NightscoutDayReportView: View {
    let date: Date

    var body: some View {
        NightscoutDayReportControllerRepresentable(date: date)
            .ignoresSafeArea()
    }
}

struct NightscoutDayReportControllerRepresentable: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let date: Date

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = NightscoutDayReportViewController()
        vc.reportDate = date
        vc.onClose = { dismiss() }
        let nav = UINavigationController(rootViewController: vc)
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        if let vc = uiViewController.viewControllers.first as? NightscoutDayReportViewController {
            vc.reportDate = date
        }
    }
}

final class NightscoutDayReportViewController: UIViewController, WKNavigationDelegate {

    var onClose: (() -> Void)?
    private var currentReportType: String = "daytoday"
    private var toggleReportButton: UIBarButtonItem!
    private var glucoseDistributionButton: UIBarButtonItem!
    private var currentStartDate: Date?
    private var currentEndDate: Date?

    var reportDate: Date? {
        didSet {
            if isViewLoaded {
                setupNavigationBar()
                reloadNightscoutPage()
            }
        }
    }

    private var webView: WKWebView!
    private var overlayView: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupNavigationBar()
        setupWebView()
        setupOverlayView()
        reloadNightscoutPage()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Lås orienteringen till liggande för bäst visning
        AppDelegate.AppUtility.lockOrientation(.landscape, andRotateTo: .landscapeRight)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Återställ orientering när vi lämnar – lås appen till stående läge igen
        AppDelegate.AppUtility.lockOrientation(.portrait, andRotateTo: .portrait)
        webView?.stopLoading()
    }

    private func setupNavigationBar() {
        if let date = reportDate {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            let formatted = df.string(from: date)
            self.title = formatted
        } else {
            self.title = "Nightscout"
        }

        let closeButton = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeTapped))
        navigationItem.leftBarButtonItem = closeButton

        let previousDayButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(loadPreviousDay)
        )
        let nextDayButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.right"),
            style: .plain,
            target: self,
            action: #selector(loadNextDay)
        )
        toggleReportButton = UIBarButtonItem(
            image: UIImage(systemName: "gauge.with.dots.needle.67percent"),
            style: .plain,
            target: self,
            action: #selector(toggleReportType)
        )
        glucoseDistributionButton = UIBarButtonItem(
            image: UIImage(systemName: "chart.pie"),
            style: .plain,
            target: self,
            action: #selector(loadGlucoseDistributionReport)
        )

        navigationItem.rightBarButtonItems = [
            glucoseDistributionButton,
            toggleReportButton,
            nextDayButton,
            previousDayButton
        ]
    }

    @objc private func closeTapped() {
        if let onClose = onClose {
            onClose()
        } else {
            dismiss(animated: true, completion: nil)
        }
    }

    @objc private func loadPreviousDay() {
        if currentReportType == "glucosedistribution" {
            adjustGlucoseDistributionDates(by: -14)
        } else {
            adjustDate(by: -1)
        }
    }

    @objc private func loadNextDay() {
        if currentReportType == "glucosedistribution" {
            adjustGlucoseDistributionDates(by: 14)
        } else {
            adjustDate(by: 1)
        }
    }

    private func adjustGlucoseDistributionDates(by days: Int) {
        let calendar = Calendar.current
        let today = Date()

        if let endDate = currentEndDate {
            let newEndDate = calendar.date(byAdding: .day, value: days, to: endDate)!

            let finalEndDate = min(newEndDate, today)
            let finalStartDate = calendar.date(byAdding: .day, value: -13, to: finalEndDate)!

            currentStartDate = finalStartDate
            currentEndDate = finalEndDate

            reloadNightscoutPage(startDate: currentStartDate, endDate: currentEndDate)
        }
    }

    @objc private func toggleReportType() {
        currentReportType = (currentReportType == "daytoday") ? "dailystats" : "daytoday"
        reloadNightscoutPage()
    }

    @objc private func loadGlucoseDistributionReport() {
        let calendar = Calendar.current
        let today = Date()

        // Använd det datum som valdes i DailyStats (reportDate) som slutdatum om det finns,
        // annars fall tillbaka till idag. Klampa för säkerhets skull så vi inte hamnar i framtiden.
        let baseEndDate = reportDate ?? today
        let effectiveEndDate = min(baseEndDate, today)

        currentEndDate = effectiveEndDate
        currentStartDate = calendar.date(byAdding: .day, value: -13, to: effectiveEndDate)

        currentReportType = "glucosedistribution"
        reloadNightscoutPage(startDate: currentStartDate, endDate: currentEndDate)
    }

    private func adjustDate(by days: Int) {
        guard let currentDate = reportDate else { return }
        let calendar = Calendar.current
        reportDate = calendar.date(byAdding: .day, value: days, to: currentDate)
        setupNavigationBar()
        reloadNightscoutPage()
    }

    private func updateToggleReportButtonIcon() {
        let iconName = (currentReportType == "daytoday")
            ? "gauge.with.dots.needle.67percent"
            : "chart.dots.scatter"
        toggleReportButton.image = UIImage(systemName: iconName)
    }

    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        view.addSubview(webView)

        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func setupOverlayView() {
        overlayView = UIView(frame: view.bounds)
        overlayView.backgroundColor = .systemBackground
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(overlayView)

        let imageView = UIImageView(image: UIImage(named: "nightscout")?.withRenderingMode(.alwaysTemplate))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .systemGray
        overlayView.addSubview(imageView)

        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.color = .systemGray
        activityIndicator.startAnimating()
        overlayView.addSubview(activityIndicator)

        let fetchingLabel = UILabel()
        fetchingLabel.translatesAutoresizingMaskIntoConstraints = false
        fetchingLabel.text = NSLocalizedString("Hämtar rapport", comment: "Fetching report text")
        fetchingLabel.textAlignment = .center
        fetchingLabel.textColor = .systemGray

        let systemFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
        if let roundedDescriptor = systemFont.fontDescriptor.withDesign(.rounded) {
            fetchingLabel.font = UIFont(descriptor: roundedDescriptor, size: 14)
        } else {
            fetchingLabel.font = systemFont
        }

        overlayView.addSubview(fetchingLabel)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            imageView.bottomAnchor.constraint(equalTo: activityIndicator.topAnchor, constant: -12),
            imageView.heightAnchor.constraint(equalToConstant: 80),

            activityIndicator.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: overlayView.centerYAnchor),

            fetchingLabel.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            fetchingLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 12)
        ])
    }

    private func reloadNightscoutPage(startDate: Date? = nil, endDate: Date? = nil) {
        let baseURL = ObservableUserDefaults.shared.url.value
        let token = UserDefaultsRepository.token.value

        let reportStartDate = startDate ?? reportDate
        let reportEndDate = endDate ?? reportDate

        guard !baseURL.isEmpty, !token.isEmpty,
              let reportStartDate = reportStartDate,
              let reportEndDate = reportEndDate else {
            return
        }

        var urlString = baseURL
        if !urlString.hasSuffix("/") {
            urlString += "/"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let startString = dateFormatter.string(from: reportStartDate)
        let endString = dateFormatter.string(from: reportEndDate)

        var components = URLComponents(string: urlString + "report/")
        components?.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "report", value: currentReportType),
            URLQueryItem(name: "startDate", value: startString),
            URLQueryItem(name: "endDate", value: endString),
            URLQueryItem(name: "autoShow", value: "true"),
            URLQueryItem(name: "hideMenu", value: "true")
        ]

        guard let url = components?.url else {
            return
        }

        overlayView.alpha = 1
        overlayView.isHidden = false
        view.bringSubviewToFront(overlayView)

        updateToggleReportButtonIcon()
        loadNightscoutPage(with: url)
    }

    private func loadNightscoutPage(with url: URL) {
        let urlString = url.absoluteString
        let wrapperHTML = """
        <!DOCTYPE html>
        <html style=\"background:transparent; height:100%;\">
          <head>
            <meta name=\"viewport\" content=\"width=device-width, initial-scale=1, user-scalable=no\"/>
            <style>
              html, body { height: 100%; margin: 0; background: transparent; overflow: hidden; }
              #wrap { position: relative; width: 100%; height: 100%; background: transparent; }
              #inner { position: absolute; top: 0; left: 0; transform-origin: top left; }
              iframe { border: 0; display: block; background: transparent; }
            </style>
          </head>
          <body>
            <div id=\"wrap\">
              <div id=\"inner\">
                <iframe id=\"ns\" src=\"\(urlString)\" allowtransparency=\"true\" style=\"background:transparent; width:1200px; height:800px;\"></iframe>
              </div>
            </div>
            <script>
              (function() {
                var BASE_W = 1200;
                function fit() {
                  var wrap = document.getElementById('wrap');
                  var inner = document.getElementById('inner');
                  var iframe = document.getElementById('ns');
                  var W = wrap.clientWidth;
                  var H = wrap.clientHeight;
                  if (W === 0 || H === 0) return;
                  var scale = W / BASE_W;
                  inner.style.transform = 'scale(' + scale + ')';
                  var ih = Math.ceil(H / scale);
                  iframe.style.height = ih + 'px';
                }
                window.addEventListener('resize', fit);
                var attempts = 0;
                var t = setInterval(function(){
                  fit();
                  attempts++;
                  if (attempts > 10) clearInterval(t);
                }, 100);
                document.addEventListener('DOMContentLoaded', fit);
              })();
            </script>
          </body>
        </html>
        """
        webView.loadHTMLString(wrapperHTML, baseURL: nil)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        fadeOutOverlay()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fadeOutOverlay()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fadeOutOverlay()
    }

    private func fadeOutOverlay() {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.5, animations: {
                self.overlayView.alpha = 0
            }) { _ in
                self.overlayView.isHidden = true
            }
        }
    }
}
