import Foundation
import MangaLadaCore

// A model comparison, not an automatic claim about semantic accuracy. Review the saved text.
enum TextTranslationBenchmark {
    static func run(input: URL, output: URL, configuration: LocalTranslatorConfiguration) async throws {
        guard !FileManager.default.fileExists(atPath: output.path) else { throw BenchmarkError.reportAlreadyExists }
        let source = try Data(contentsOf: input)
        let cases = try JSONDecoder().decode([TranslationCase].self, from: source)
        guard !cases.isEmpty, Set(cases.map(\.id)).count == cases.count,
              cases.allSatisfy(\.isValid) else {
            throw BenchmarkError.invalidCases
        }
        let began = Date()
        let pipeline = TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean,
            maskedResolver: MaskedContextResolver(directory: output.deletingLastPathComponent().appendingPathComponent("ContextInterpretations")))
        var reports: [CaseReport] = []
        for test in cases {
            try Task.checkCancellation()
            reports.append(try await evaluate(test, pipeline: pipeline, configuration: configuration))
        }
        guard source == (try Data(contentsOf: input)) else { throw BenchmarkError.sourceChanged }
        let report = Report(model: configuration.ollama.model, startedAt: began, elapsed: Date().timeIntervalSince(began), cases: reports)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: output, options: .withoutOverwriting)
        guard reports.allSatisfy({ $0.failure == nil }) else { throw BenchmarkError.failedCases }
        print("Text benchmark saved: \(cases.count) cases. Read each output to assess meaning; timings exclude OCR and typesetting.")
    }

    private static func evaluate(_ test: TranslationCase, pipeline: TranslationPipeline,
                                 configuration: LocalTranslatorConfiguration) async throws -> CaseReport {
        let height = 1 / Double(test.texts.count)
        let blocks = test.texts.enumerated().map { index, text in
            TextBlock(box: TextBox(x: 0.1, y: Double(index) * height, width: 0.8, height: height * 0.8), originalText: text,
                      translatedText: test.reviewedTexts?[index] ?? "", textKind: test.kinds?[index])
        }
        let began = Date()
        do {
            let translated: [TextBlock]
            if let indices = test.selectedIndices {
                let ids = Set(indices.map { blocks[$0].id })
                translated = try await pipeline.translateSelected(ids, in: blocks, configuration: configuration, previousContext: test.previousContext ?? "")
                guard blocks.filter({ !ids.contains($0.id) }).allSatisfy({ translated.contains($0) }) else {
                    throw BenchmarkError.unselectedTextChanged
                }
            } else {
                translated = try await pipeline.translate(blocks, configuration: configuration, previousContext: test.previousContext ?? "")
            }
            guard translated.count == blocks.count, Set(translated.map(\.id)) == Set(blocks.map(\.id)) else {
                throw BenchmarkError.regionIdentityChanged
            }
            let result = CaseReport(input: test, elapsed: Date().timeIntervalSince(began), translations: translated, failure: nil)
            print("\(test.id): \(translated.count) regions, \(String(format: "%.2f", result.elapsed))s"); fflush(stdout)
            return result
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            print("\(test.id): FAILED: \(error.localizedDescription)"); fflush(stdout)
            return CaseReport(input: test, elapsed: Date().timeIntervalSince(began), translations: [], failure: error.localizedDescription)
        }
    }

    private struct TranslationCase: Codable {
        let id: String
        let texts: [String]
        let previousContext: String?
        let reviewPoints: [String]
        let kinds: [MangaTextKind]?
        let reviewedTexts: [String]?
        let selectedIndices: [Int]?

        var isValid: Bool {
            guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !texts.isEmpty,
                  texts.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  kinds == nil || kinds?.count == texts.count,
                  reviewedTexts == nil || reviewedTexts?.count == texts.count else { return false }
            guard let selectedIndices else { return true }
            return Set(selectedIndices).count == selectedIndices.count && selectedIndices.allSatisfy { texts.indices.contains($0) }
        }
    }
    private struct CaseReport: Encodable {
        let input: TranslationCase
        let elapsed: Double
        let translations: [TextBlock]
        let failure: String?
    }
    private struct Report: Encodable {
        let model: String
        let startedAt: Date
        let elapsed: Double
        let cases: [CaseReport]
    }
    private enum BenchmarkError: LocalizedError {
        case reportAlreadyExists, invalidCases, sourceChanged, failedCases, regionIdentityChanged, unselectedTextChanged
        var errorDescription: String? {
            switch self {
            case .reportAlreadyExists: "이미 있는 보고서는 덮어쓰지 않습니다. 새 출력 파일을 지정해주세요."
            case .invalidCases: "비교할 문장이 비어 있거나 사례 번호가 중복되었습니다."
            case .sourceChanged: "검수 중 입력 파일이 변경되었습니다."
            case .failedCases: "일부 응답이 검증에 실패했습니다. 저장된 보고서에서 실패 원인을 확인해주세요."
            case .regionIdentityChanged: "번역 전후의 영역 번호가 달라졌습니다."
            case .unselectedTextChanged: "선택하지 않은 영역의 검수 내용이 바뀌었습니다."
            }
        }
    }
}
