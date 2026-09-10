//
//  HuggingFaceApp.swift
//  Hugging Face
//
//  Created by Enrique Hernández Calabrés on 05/08/2026.
//

import AppKit
import SwiftUI
import Combine

@main
struct HuggingFaceApp: App {
    @StateObject private var viewModel: DashboardViewModel

    init() {
        HuggingFacePreferences.migrateSandboxPreferences()
        let jobsAPI = HuggingFaceJobsAPI(
            baseURL: URL(string: "https://huggingface.co")!,
            tokenProvider: { KeychainService.loadToken() },
            namespaceProvider: { HuggingFacePreferences.namespace }
        )
        let endpointsAPI = HuggingFaceEndpointsAPI(
            tokenProvider: { KeychainService.loadToken() },
            namespaceProvider: { HuggingFacePreferences.namespace }
        )
        let billingAPI = HuggingFaceBillingAPI(
            tokenProvider: { KeychainService.loadToken() }
        )
        let viewModel = DashboardViewModel(
            jobsAPI: jobsAPI,
            endpointsAPI: endpointsAPI,
            billingAPI: billingAPI
        )
        _viewModel = StateObject(wrappedValue: viewModel)
        viewModel.start()
        AppUpdateService.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardMenuContent()
                .environmentObject(viewModel)
                .frame(width: 420)
        } label: {
            HuggingFaceMenuBarLabel()
                .environmentObject(viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

struct HuggingFaceMenuBarLabel: View {
    @EnvironmentObject private var vm: DashboardViewModel
    @AppStorage(HuggingFacePreferences.showActiveCountKey) private var showActiveCount = true

    var body: some View {
        HStack(spacing: 3) {
            HuggingFaceIconView(size: 20)

            if showActiveCount && vm.activityCount > 0 {
                Text("\(vm.activityCount)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hugging Face")
        .accessibilityValue(
            "\(vm.activityCount) total items: \(vm.running.count) active jobs, \(vm.scheduled.count) scheduled jobs, \(vm.endpoints.count) endpoints"
        )
    }
}

struct HuggingFaceIconView: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: sizedImage)
            .renderingMode(.original)
            .frame(width: size, height: size)
            .clipped()
    }

    private var sizedImage: NSImage {
        guard let source = NSImage(named: "HFIcon"),
              let image = source.copy() as? NSImage else {
            return NSImage(size: NSSize(width: size, height: size))
        }

        image.size = NSSize(width: size, height: size)
        return image
    }
}

struct HuggingFaceHeaderIconView: View {
    var body: some View {
        Image("HFHeaderIcon")
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 30, height: 30)
    }
}
