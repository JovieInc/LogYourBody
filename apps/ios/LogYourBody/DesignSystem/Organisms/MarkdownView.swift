//
// MarkdownView.swift
// LogYourBody
//
import SwiftUI

// MARK: - Markdown View Organism

struct MarkdownView: View {
    let markdown: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(parseMarkdownSections(markdown), id: \.id) { section in
                MarkdownSectionView(section: section)
            }
        }
    }
    
    private func parseMarkdownSections(_ markdown: String) -> [MarkdownSection] {
        var sections: [MarkdownSection] = []
        let lines = markdown.components(separatedBy: .newlines)
        var currentSection: MarkdownSection?
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.isEmpty {
                if let section = currentSection {
                    sections.append(section)
                    currentSection = nil
                }
            } else if trimmed.hasPrefix("# ") {
                if let section = currentSection { sections.append(section) }
                currentSection = MarkdownSection(type: .h1, content: String(trimmed.dropFirst(2)))
            } else if trimmed.hasPrefix("## ") {
                if let section = currentSection { sections.append(section) }
                currentSection = MarkdownSection(type: .h2, content: String(trimmed.dropFirst(3)))
            } else if trimmed.hasPrefix("### ") {
                if let section = currentSection { sections.append(section) }
                currentSection = MarkdownSection(type: .h3, content: String(trimmed.dropFirst(4)))
            } else if trimmed.hasPrefix("**") && trimmed.hasSuffix("**") && trimmed.count > 4 {
                if let section = currentSection { sections.append(section) }
                let content = String(trimmed.dropFirst(2).dropLast(2))
                currentSection = MarkdownSection(type: .bold, content: content)
            } else if trimmed.hasPrefix("- ") {
                if let section = currentSection { sections.append(section) }
                currentSection = MarkdownSection(type: .bulletPoint, content: String(trimmed.dropFirst(2)))
            } else if trimmed.hasPrefix("---") {
                if let section = currentSection { sections.append(section) }
                sections.append(MarkdownSection(type: .divider, content: ""))
                currentSection = nil
            } else {
                if let section = currentSection, section.type == .paragraph {
                    currentSection = MarkdownSection(type: .paragraph, content: section.content + " " + trimmed)
                } else {
                    if let section = currentSection { sections.append(section) }
                    currentSection = MarkdownSection(type: .paragraph, content: trimmed)
                }
            }
        }
        
        if let section = currentSection {
            sections.append(section)
        }
        
        return sections
    }
}

// MARK: - Markdown Section Model

struct MarkdownSection: Identifiable {
    let id = UUID()
    let type: MarkdownType
    let content: String
    
    enum MarkdownType {
        case h1, h2, h3, paragraph, bold, bulletPoint, divider
    }
}

// MARK: - Markdown Section View

struct MarkdownSectionView: View {
    let section: MarkdownSection
    
    var body: some View {
        switch section.type {
        case .h1:
            DSText(
                section.content,
                style: .largeTitle,
                weight: .bold,
                color: .appText
            )
            .padding(.top, 20)
            .padding(.bottom, 10)
        
        case .h2:
            DSText(
                section.content,
                style: .title2,
                weight: .semibold,
                color: .appText
            )
            .padding(.top, 16)
            .padding(.bottom, 8)
        
        case .h3:
            DSText(
                section.content,
                style: .headline,
                weight: .medium,
                color: .appText
            )
            .padding(.top, 12)
            .padding(.bottom, 4)
        
        case .paragraph:
            Text(parseInlineMarkdown(section.content))
                .font(.body)
                .foregroundColor(.appTextSecondary)
                .lineSpacing(4)
        
        case .bold:
            DSText(
                section.content,
                style: .body,
                weight: .semibold,
                color: .appText
            )
        
        case .bulletPoint:
            HStack(alignment: .top, spacing: 8) {
                DSText("•", style: .body, color: .appTextSecondary)
                Text(parseInlineMarkdown(section.content))
                    .font(.body)
                    .foregroundColor(.appTextSecondary)
                    .lineSpacing(4)
                Spacer()
            }
            .padding(.leading, 16)
        
        case .divider:
            DSDivider()
                .padding(.vertical, 20)
        }
    }
    
    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        var attributedString = AttributedString(text)
        
        // Parse bold text
        if let boldRegex = try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*", options: []) {
            let nsString = text as NSString
            let matches = boldRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in matches.reversed() {
                if let range = Range(match.range, in: text) {
                    let boldText = String(text[range]).replacingOccurrences(of: "**", with: "")
                    if let attrRange = Range(match.range, in: attributedString) {
                        attributedString.replaceSubrange(attrRange, with: AttributedString(boldText))
                        if let newRange = attributedString.range(of: boldText) {
                            attributedString[newRange].font = .body.bold()
                        }
                    }
                }
            }
        }
        
        return attributedString
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        MarkdownView(
            markdown: """
            # Privacy Policy
            
            **Last Updated: July 11, 2025**
            
            ## Introduction
            
            We take your privacy seriously. This policy describes how we collect and use your data.
            
            ### Data Collection
            
            We collect the following types of data:
            - Personal information (name, email)
            - Health metrics
            - Usage analytics
            
            ---
            
            ## Your Rights
            
            You have the right to:
            - Access your data
            - Delete your account
            - Export your information
            
            **Contact us** if you have any questions.
            """
        )
        .padding()
    }
    .background(Color.appBackground)
}
