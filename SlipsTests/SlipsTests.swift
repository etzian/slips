import Testing
import SlipsCore

@Test func appLinksCore() throws {
    #expect(try AppDatabase.inMemory().appliedMigrations().contains("v1_initial"))
}
