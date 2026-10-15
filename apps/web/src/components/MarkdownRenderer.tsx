import ReactMarkdown from 'react-markdown';

export function MarkdownRenderer({
  content,
  className = '',
}: {
  content: string;
  className?: string;
}) {
  return (
    <div className={`text-secondary-token space-y-6 text-base leading-7 ${className}`}>
      <ReactMarkdown
        components={{
          h1: ({ children }) => (
            <h1 className="text-primary-token mb-8 text-4xl leading-tight font-bold">{children}</h1>
          ),
          h2: ({ children }) => (
            <h2 className="text-primary-token mt-10 mb-4 text-2xl leading-tight font-semibold">
              {children}
            </h2>
          ),
          h3: ({ children }) => (
            <h3 className="text-primary-token mt-8 mb-3 text-xl font-semibold">{children}</h3>
          ),
          ul: ({ children }) => <ul className="list-disc space-y-3 pl-6">{children}</ul>,
          ol: ({ children }) => <ol className="list-decimal space-y-3 pl-6">{children}</ol>,
          a: ({ children, href }) => (
            <a
              href={href}
              className="focus-visible:outline-focus break-words underline underline-offset-4 focus-visible:outline-2"
            >
              {children}
            </a>
          ),
          hr: () => <hr className="border-subtle my-8" />,
        }}
      >
        {content}
      </ReactMarkdown>
    </div>
  );
}
