import MangaLadaCore

extension AppState {
    func translationContext(before index: Int) -> String {
        let successful = results.filter { failures[$0.key] == nil }.mapValues(\.translation)
        return MangaTranslationContext.previousPages(successful, before: index)
    }
}
