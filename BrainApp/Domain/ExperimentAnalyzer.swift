import Foundation

struct ExperimentReview {
    struct ArmStats {
        let arm: Experiment.Arm
        let label: String
        let count: Int
        let ratedCount: Int
        let mean: Double?
    }

    let a: ArmStats
    let b: ArmStats
    /// Plain-language reading. Never claims causality.
    let verdict: String
}

/// Compares an experiment's two conditions using the linked entries.
enum ExperimentAnalyzer {
    static let minimumPerArm = 3
    static let minimumDifference = 0.5

    static func review(_ experiment: Experiment, activities: [Activity]) -> ExperimentReview {
        let linked = activities.filter { $0.experimentID == experiment.id }

        func stats(_ arm: Experiment.Arm) -> ExperimentReview.ArmStats {
            let items = linked.filter { $0.experimentArm == arm }
            let values = items.compactMap { $0.rating(experiment.measure) }
            let mean = values.isEmpty ? nil : Double(values.reduce(0, +)) / Double(values.count)
            return ExperimentReview.ArmStats(arm: arm, label: experiment.label(for: arm), count: items.count,
                                             ratedCount: values.count, mean: mean)
        }

        let a = stats(.a)
        let b = stats(.b)
        let measure = experiment.measure.inSentence
        let caveat = "A simple personal experiment doesn't prove causality: the task, rest and context matter too."

        guard a.ratedCount >= minimumPerArm, b.ratedCount >= minimumPerArm,
              let meanA = a.mean, let meanB = b.mean else {
            return ExperimentReview(a: a, b: b, verdict: "Not enough data to compare: you need at least \(minimumPerArm) \(measure) ratings for each condition. You can keep logging or close it as is; that is a valid result too.")
        }

        if abs(meanA - meanB) < minimumDifference {
            return ExperimentReview(a: a, b: b, verdict: "Your entries show no clear difference in \(measure) between the two conditions. \(caveat)")
        }

        let better = meanA > meanB ? a : b
        let betterMean = max(meanA, meanB)
        let worseMean = min(meanA, meanB)
        return ExperimentReview(a: a, b: b, verdict: "In your entries, \(measure) was higher with “\(better.label)” (\(format(betterMean)) vs \(format(worseMean))). \(caveat)")
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
