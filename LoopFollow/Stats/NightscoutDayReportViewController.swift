//
//  NightscoutDayReportViewController.swift
//  LoopFollow
//
//

import UIKit
import WebKit

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
/*
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(closeTapped))
        navigationItem.rightBarButtonItem = doneButton
*/
        let doneButton = UIBarButtonItem(title: "Klar", style: .plain, target: self, action: #selector(closeTapped))
        navigationItem.rightBarButtonItem = doneButton

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

        navigationItem.leftBarButtonItems = [
            glucoseDistributionButton,
            toggleReportButton,
            previousDayButton,
            nextDayButton
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

