import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct DashboardMetricsList<CardContent: View>: View {
    typealias MetricIdentifier = DashboardViewLiquid.MetricIdentifier

    @Binding var metricsOrder: [MetricIdentifier]
    @Binding var draggedMetric: MetricIdentifier?
    @Binding var dropTargetMetric: MetricIdentifier?
    let onReorder: () -> Void
    private let cardContent: (MetricIdentifier) -> CardContent

    init(
        metricsOrder: Binding<[MetricIdentifier]>,
        draggedMetric: Binding<MetricIdentifier?>,
        dropTargetMetric: Binding<MetricIdentifier?>,
        onReorder: @escaping () -> Void,
        @ViewBuilder cardContent: @escaping (MetricIdentifier) -> CardContent
    ) {
        _metricsOrder = metricsOrder
        _draggedMetric = draggedMetric
        _dropTargetMetric = dropTargetMetric
        self.onReorder = onReorder
        self.cardContent = cardContent
    }

    var body: some View {
        VStack(spacing: 14) {
            ForEach(metricsOrder) { metricId in
                cardContent(metricId)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(
                                (draggedMetric == metricId || dropTargetMetric == metricId) ?
                                    Color.metricAccent.opacity(draggedMetric == metricId ? 0.9 : 0.6) :
                                    Color.clear,
                                lineWidth: draggedMetric == metricId ? 2 : (dropTargetMetric == metricId ? 1.5 : 0)
                            )
                    )
                    .scaleEffect(draggedMetric == metricId ? 1.03 : 1.0)
                    .opacity(1.0)
                    .shadow(
                        color: draggedMetric == metricId ? Color.black.opacity(0.45) : Color.clear,
                        radius: draggedMetric == metricId ? 18 : 0,
                        x: 0,
                        y: draggedMetric == metricId ? 10 : 0
                    )
                    .zIndex(draggedMetric == metricId ? 1 : 0)
                    .onDrag {
                        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.85)) {
                            draggedMetric = metricId
                            dropTargetMetric = metricId
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
                            dropTargetMetric: $dropTargetMetric,
                            onReorder: onReorder
                        )
                    )
            }
        }
        .animation(
            .interactiveSpring(response: 0.30, dampingFraction: 0.85),
            value: metricsOrder
        )
        .animation(
            .interactiveSpring(response: 0.28, dampingFraction: 0.90),
            value: draggedMetric
        )
        .animation(
            .easeOut(duration: 0.16),
            value: dropTargetMetric
        )
    }
}

private struct DashboardMetricDropDelegate: DropDelegate {
    typealias MetricIdentifier = DashboardViewLiquid.MetricIdentifier

    let metric: MetricIdentifier
    @Binding var metrics: [MetricIdentifier]
    @Binding var draggedMetric: MetricIdentifier?
    @Binding var dropTargetMetric: MetricIdentifier?
    let onReorder: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        draggedMetric = nil
        dropTargetMetric = nil
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
        dropTargetMetric = metric
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropTargetMetric == metric {
            dropTargetMetric = nil
        }
    }
}
