extension PokiEntry.Request {
    enum Outcome: String { case started, returned, shown, blocked, invalidated }

    @MainActor
    func record(_ outcome: Outcome, reason: String, session: Int? = nil) {
        let talk = session.map { " session=\($0)" } ?? ""
        AppLog.shared.add("voice", "launch request=\(id.uuidString) source=\(source.rawValue) result=\(outcome.rawValue) reason=\(reason)\(talk)")
    }
}
