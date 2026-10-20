'use client';

import React from 'react';

interface MarkdownRendererProps {
  content: string;
  className?: string;
}

export function MarkdownRenderer({ content, className = '' }: MarkdownRendererProps) {
  // Parse markdown content into sections
  const sections = React.useMemo(() => {
    const lines = content.split('\n');
    const parsedSections: Array<{ type: string; content: string; level?: number }> = [];
    let currentParagraph: string[] = [];

    lines.forEach((line) => {
      const trimmed = line.trim();

      // Skip empty lines but save current paragraph
      if (!trimmed) {
        if (currentParagraph.length > 0) {
          parsedSections.push({
            type: 'paragraph',
            content: currentParagraph.join(' ')
          });
          currentParagraph = [];
        }
        return;
      }

      // Headers
      if (trimmed.startsWith('### ')) {
        if (currentParagraph.length > 0) {
          parsedSections.push({
            type: 'paragraph',
            content: currentParagraph.join(' ')
          });
          currentParagraph = [];
        }
        parsedSections.push({
          type: 'header',
          level: 3,
          content: trimmed.substring(4)
        });
      } else if (trimmed.startsWith('## ')) {
        if (currentParagraph.length > 0) {
          parsedSections.push({
            type: 'paragraph',
            content: currentParagraph.join(' ')
          });
          currentParagraph = [];
        }
        parsedSections.push({
          type: 'header',
          level: 2,
          content: trimmed.substring(3)
        });
      } else if (trimmed.startsWith('# ')) {
        if (currentParagraph.length > 0) {
          parsedSections.push({
            type: 'paragraph',
            content: currentParagraph.join(' ')
          });
          currentParagraph = [];
        }
        parsedSections.push({
          type: 'header',
          level: 1,
          content: trimmed.substring(2)
        });
      }
      // Bullet points
      else if (trimmed.startsWith('- ')) {
        if (currentParagraph.length > 0) {
          parsedSections.push({
            type: 'paragraph',
            content: currentParagraph.join(' ')
          });
          currentParagraph = [];
        }
        parsedSections.push({
          type: 'bullet',
          content: trimmed.substring(2)
        });
      }
      // Numbered lists
      else if (/^\d+\.\s/.test(trimmed)) {
        if (currentParagraph.length > 0) {
          parsedSections.push({
            type: 'paragraph',
            content: currentParagraph.join(' ')
          });
          currentParagraph = [];
        }
        const content = trimmed.replace(/^\d+\.\s/, '');
        parsedSections.push({
          type: 'numbered',
          content: content
        });
      }
      // Horizontal rule
      else if (trimmed === '---') {
        if (currentParagraph.length > 0) {
          parsedSections.push({
            type: 'paragraph',
            content: currentParagraph.join(' ')
          });
          currentParagraph = [];
        }
        parsedSections.push({
          type: 'divider',
          content: ''
        });
      }
      // Regular paragraph content
      else {
        currentParagraph.push(trimmed);
      }
    });

    // Don't forget the last paragraph
    if (currentParagraph.length > 0) {
      parsedSections.push({
        type: 'paragraph',
        content: currentParagraph.join(' ')
      });
    }

    return parsedSections;
  }, [content]);

  // Render inline markdown (bold, links, etc.)
  const renderInline = (text: string) => {
    // Replace **bold** text
    const parts = text.split(/\*\*(.+?)\*\*/g);
    
    return parts.map((part, index) => {
      // Odd indices are bold text
      if (index % 2 === 1) {
        return <strong key={index} className="font-semibold">{part}</strong>;
      }
      
      // Process links in non-bold text
      const linkParts = part.split(/\[(.+?)\]\((.+?)\)/g);
      
      return linkParts.map((linkPart, linkIndex) => {
        // Pattern: text, link text, link url, text, link text, link url...
        if (linkIndex % 3 === 1) {
          // This is link text, next part is URL
          const url = linkParts[linkIndex + 1];
          return (
            <a
              key={`${index}-${linkIndex}`}
              href={url}
              className="text-linear-purple hover:text-linear-purple-light underline"
              target="_blank"
              rel="noopener noreferrer"
            >
              {linkPart}
            </a>
          );
        } else if (linkIndex % 3 === 2) {
          // This is URL part, skip it as it's already processed
          return null;
        }
        
        // Regular text
        return <React.Fragment key={`${index}-${linkIndex}`}>{linkPart}</React.Fragment>;
      }).filter(Boolean);
    });
  };

  return (
    <div className={`prose prose-lg dark:prose-invert max-w-none space-y-6 ${className}`}>
      {sections.map((section, index) => {
        switch (section.type) {
          case 'header':
            if (section.level === 1) {
              return (
                <h1 key={index} className="text-4xl font-bold mb-8 text-linear-text">
                  {renderInline(section.content)}
                </h1>
              );
            } else if (section.level === 2) {
              return (
                <h2 key={index} className="text-2xl font-semibold mt-8 mb-4 text-linear-text">
                  {renderInline(section.content)}
                </h2>
              );
            } else {
              return (
                <h3 key={index} className="text-xl font-semibold mt-6 mb-3 text-linear-text">
                  {renderInline(section.content)}
                </h3>
              );
            }

          case 'paragraph':
            return (
              <p key={index} className="text-linear-text-secondary leading-relaxed">
                {renderInline(section.content)}
              </p>
            );

          case 'bullet':
            return (
              <li key={index} className="list-disc ml-6 text-linear-text-secondary">
                {renderInline(section.content)}
              </li>
            );

          case 'numbered':
            return (
              <li key={index} className="list-decimal ml-6 text-linear-text-secondary">
                {renderInline(section.content)}
              </li>
            );

          case 'divider':
            return <hr key={index} className="my-8 border-linear-border" />;

          default:
            return null;
        }
      })}
    </div>
  );
}