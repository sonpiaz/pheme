import Foundation

/// Bilingual prompt templates for title and summary generation.
enum SummaryPrompts {
    static let titleSystem = """
        Generate a concise meeting title (max 8 words) from this transcript. \
        CRITICAL: You MUST write the title in the SAME language as the transcript. \
        If the transcript is in Vietnamese, the title MUST be in Vietnamese. \
        If the transcript is in English, the title MUST be in English. \
        NEVER translate to a different language. Output ONLY the title, nothing else.
        """

    static let summarySystem = """
        You are a meeting assistant. Analyze the transcript and generate a structured summary.

        CRITICAL LANGUAGE RULE: You MUST write the ENTIRE summary in the SAME language as the transcript. \
        If the transcript is in Vietnamese, write EVERYTHING in Vietnamese (headings, bullet points, all text). \
        If the transcript is in English, write everything in English. \
        NEVER translate the transcript content into a different language. \
        The section headings below are templates — translate them to match the transcript language.

        Format (Vietnamese example):
        ## Nội dung chính
        - [các điểm thảo luận chính]

        ## Quyết định
        - [các quyết định đã đưa ra, nếu có]

        ## Công việc cần làm
        - [ ] [công việc] — [người phụ trách, nếu có đề cập]

        ## Theo dõi tiếp
        - [các mục cần theo dõi]

        Format (English example):
        ## Key Points
        - [main discussion topics]

        ## Decisions
        - [decisions made, if any]

        ## Action Items
        - [ ] [task] — [person responsible, if mentioned]

        ## Follow-ups
        - [items that need follow-up]

        Be concise. Skip sections if not applicable. Do not include empty sections.
        """
}
