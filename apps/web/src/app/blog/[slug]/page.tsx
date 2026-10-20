import { getAllSlugs, getPostBySlug, getAllPosts } from '@/lib/blog';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Header } from '@/components/Header';
import { Footer } from '@/components/Footer';
import Link from 'next/link';
import { Calendar, Clock, User, ArrowLeft, Activity } from 'lucide-react';
import { Metadata } from 'next';
import { notFound } from 'next/navigation';
import ReactMarkdown from 'react-markdown';

interface BlogPostPageProps {
  params: Promise<{
    slug: string;
  }>;
}

export async function generateStaticParams() {
  const slugs = await getAllSlugs();
  return slugs.map((slug) => ({
    slug,
  }));
}

export async function generateMetadata({ params }: BlogPostPageProps): Promise<Metadata> {
  const { slug } = await params;
  const post = await getPostBySlug(slug);
  
  if (!post) {
    return {
      title: 'Post Not Found - LogYourBody',
    };
  }

  return {
    title: `${post.title} - LogYourBody Blog`,
    description: post.excerpt,
    openGraph: {
      title: post.title,
      description: post.excerpt,
      type: 'article',
      publishedTime: post.date,
      authors: [post.author],
      tags: post.tags,
    },
  };
}

export default async function BlogPostPage({ params }: BlogPostPageProps) {
  const { slug } = await params;
  const post = await getPostBySlug(slug);
  
  if (!post) {
    notFound();
  }

  // Get related posts (same tags, excluding current post)
  const allPosts = await getAllPosts();
  const relatedPosts = allPosts
    .filter(p => p.slug !== post.slug && p.tags.some(tag => post.tags.includes(tag)))
    .slice(0, 3);

  return (
    <div className="min-h-screen bg-linear-bg font-inter">
      <Header />
      
      {/* Article Header */}
      <div className="border-b border-linear-border">
        <div className="container mx-auto px-4 sm:px-6 py-8">
          <Link href="/blog">
            <Button variant="ghost" className="text-linear-text-secondary hover:text-linear-text mb-6">
              <ArrowLeft className="h-4 w-4 mr-2" />
              Back to Blog
            </Button>
          </Link>
          
          <div className="max-w-4xl">
            <div className="flex flex-wrap items-center gap-2 mb-4">
              {post.tags.map((tag) => (
                <Badge 
                  key={tag}
                  className="bg-linear-purple/10 text-linear-purple border-linear-purple/20"
                >
                  {tag}
                </Badge>
              ))}
            </div>
            
            <h1 className="text-3xl sm:text-4xl lg:text-5xl font-bold tracking-tight text-linear-text mb-6">
              {post.title}
            </h1>
            
            <div className="flex flex-col sm:flex-row gap-4 sm:gap-6">
              <div className="flex items-center gap-6 text-linear-text-tertiary">
                <div className="flex items-center gap-2">
                  <User className="h-4 w-4" />
                  <span>{post.author}</span>
                  {post.authorRole && (
                    <span className="text-linear-text-tertiary text-sm">
                      • {post.authorRole}
                    </span>
                  )}
                </div>
                <div className="flex items-center gap-2">
                  <Calendar className="h-4 w-4" />
                  <span>{post.formattedDate}</span>
                </div>
                <div className="flex items-center gap-2">
                  <Clock className="h-4 w-4" />
                  <span>{post.readTime}</span>
                </div>
              </div>
              {post.authorStats && (
                <div className="flex items-center gap-4 text-sm">
                  <div className="flex items-center gap-1.5 px-3 py-1 bg-linear-purple/10 rounded-full">
                    <Activity className="h-3.5 w-3.5 text-linear-purple" />
                    <span className="text-linear-purple font-medium">{post.authorStats.bodyFat}% BF</span>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      </div>

      <div className="container mx-auto px-4 sm:px-6 py-12">
        <div className="grid gap-12 lg:grid-cols-4">
          {/* Main Content */}
          <div className="lg:col-span-3">
            <div className="prose prose-lg prose-invert max-w-none
              prose-headings:text-linear-text prose-headings:font-bold
              prose-p:text-linear-text-secondary prose-p:leading-relaxed
              prose-a:text-linear-purple prose-a:no-underline hover:prose-a:underline
              prose-strong:text-linear-text prose-strong:font-semibold
              prose-code:text-linear-purple prose-code:bg-linear-card prose-code:px-1 prose-code:py-0.5 prose-code:rounded prose-code:text-sm
              prose-pre:bg-linear-card prose-pre:border prose-pre:border-linear-border
              prose-blockquote:border-l-linear-purple prose-blockquote:text-linear-text-secondary
              prose-th:text-linear-text prose-td:text-linear-text-secondary
              prose-hr:border-linear-border
              prose-ul:text-linear-text-secondary prose-ol:text-linear-text-secondary
              prose-li:text-linear-text-secondary">
              <ReactMarkdown>
                {post.content}
              </ReactMarkdown>
            </div>

            {/* Call to Action */}
            <div className="mt-16 p-8 rounded-2xl border border-linear-border bg-linear-card">
              <h3 className="text-xl font-bold text-linear-text mb-4">
                Ready to Track Your Progress?
              </h3>
              <p className="text-linear-text-secondary mb-6">
                Put this knowledge into action with LogYourBody&apos;s precision tracking tools. 
                Monitor the metrics that actually matter for your fitness goals.
              </p>
              <Link href="/download/ios">
                <Button className="bg-linear-text text-linear-bg hover:bg-linear-text/90">
                  Start Free Trial
                </Button>
              </Link>
            </div>
          </div>

          {/* Sidebar */}
          <div className="lg:col-span-1">
            <div className="sticky top-8 space-y-8">
              {/* Related Posts */}
              {relatedPosts.length > 0 && (
                <Card className="border-linear-border bg-linear-card">
                  <CardHeader>
                    <CardTitle className="text-linear-text text-lg">Related Articles</CardTitle>
                  </CardHeader>
                  <CardContent className="space-y-4">
                    {relatedPosts.map((relatedPost) => (
                      <div key={relatedPost.slug}>
                        <Link 
                          href={`/blog/${relatedPost.slug}`}
                          className="text-sm font-medium text-linear-text hover:text-linear-purple transition-colors line-clamp-2"
                        >
                          {relatedPost.title}
                        </Link>
                        <p className="text-xs text-linear-text-tertiary mt-1">
                          {relatedPost.readTime}
                        </p>
                      </div>
                    ))}
                  </CardContent>
                </Card>
              )}

              {/* Share */}
              <Card className="border-linear-border bg-linear-card">
                <CardHeader>
                  <CardTitle className="text-linear-text text-lg">Share This Article</CardTitle>
                </CardHeader>
                <CardContent>
                  <p className="text-sm text-linear-text-secondary">
                    Found this helpful? Share it with someone who might benefit from evidence-based fitness content.
                  </p>
                </CardContent>
              </Card>
            </div>
          </div>
        </div>
      </div>
      
      <Footer />
    </div>
  );
}