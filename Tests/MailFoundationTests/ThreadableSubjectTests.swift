import Testing
@testable import MailFoundation

@Test("ThreadableSubject normalizes and tracks reply depth")
func threadableSubjectNormalization() {
    let cases: [(raw: String, normalized: String, depth: Int)] = [
        ("Re: simple subject", "simple subject", 1),
        ("Re: simple subject  ", "simple subject", 1),
        ("Re: Re: simple subject  ", "simple subject", 2),
        ("Re: Re[4]: simple subject  ", "simple subject", 5),
        ("Re: [Mailing-List] Re[4]: simple subject  ", "simple subject", 5),
        ("Fwd: hello", "hello", 1),
        ("(no subject)", "", 0)
    ]

    for (raw, normalized, depth) in cases {
        let result = ThreadableSubject.parse(raw)
        #expect(result.normalized == normalized)
        #expect(result.replyDepth == depth)
    }
}
