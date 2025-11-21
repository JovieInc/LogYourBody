import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct DashboardMetricsList<CardContent: View>: View {
    typealias MetricIdentifier = DashboardViewLiquid.MetricIdentifier

    @Binding var metricsOrder: [MetricIdentifier]
    @Binding var draggedMetric: MetricIdentifier?
    let onReorder: () -> Void
    private let cardContent: (MetricIdentifier) -> CardContent

    init(
        metricsOrder: Binding<[MetricIdentifier]>,
        draggedMetric: Binding<MetricIdentifier?>,
        onReorder: @escaping () -> Void,
        @ViewBuilder cardContent: @escaping (MetricIdentifier) -> CardContent
    ) {
        _metricsOrder = metricsOrder
        _draggedMetric = draggedMetric
        self.onReorder = onReorder
        self.cardContent = cardContent
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(metricsOrder) { metricId in
                cardContent(metricId)
                    .scaleEffect(draggedMetric == metricId ? 1.03 : 1.0)
                    .opacity(draggedMetric == metricId ? 0.78 : 1.0)
                    .onDrag {
                        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.85)) {
                            draggedMetric = metricId
                        }
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        return NSItemProvider(object: metricId.rawValue as NSString)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: DashboardMetricDropDelegate(
                            metric: metricId,
                            metrics: $metricsOrder,
                            draggedMetric: $draggedMetric,
                            onReorder: onReorder
                        )
                    )
            }
        }
        .animation(
            .interactiveSpring(response: 0.30, dampingFraction: 0.85),
            value: metricsOrder
        )
    }
}

private struct DashboardMetricDropDelegate: DropDelegate {
    typealias MetricIdentifier = DashboardViewLiquid.MetricIdentifier

    let metric: MetricIdentifier
    @Binding var metrics: [MetricIdentifier]
    @Binding var draggedMetric: MetricIdentifier?
    let onReorder: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        draggedMetric = nil
        onReorder()
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedMetric,
              draggedMetric != metric,
              let fromIndex = metrics.firstIndex(of: draggedMetric),
              let toIndex = metrics.firstIndex(of: metric) else {
            return
        }

        var updated = metrics
        updated.move(
            fromOffsets: IndexSet(integer: fromIndex),
            toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
        )
        metrics = updated
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        // No-op
    }
}
