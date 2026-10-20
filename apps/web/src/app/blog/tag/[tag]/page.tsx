import { getAllTags, getPostsByTag } from '@/lib/blog';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Header } from '@/components/Header';
import { Footer } from '@/components/Footer';
import Link from 'next/link';
import { Calendar, Clock, User, ArrowLeft } from 'lucide-react';
import { Metadata } from 'next';
import { notFound } from 'next/navigation';

interface TagPageProps {
  params: Promise<{
    tag: string;
  }>;
}

export async function generateStaticParams() {
  const tags = await getAllTags();
  return tags.map((tag) => ({
    tag: tag.toLowerCase().replace(/\s+/g, '-'),
  }));
}

export async function generateMetadata({ params }: TagPageProps): Promise<Metadata> {
  const { tag } = await params;
  const tagName = tag.replace(/-/g, ' ').replace(/\b\w/g, l => l.toUpperCase());
  
  return {
    title: `${tagName} Articles - LogYourBody Blog`,
    description: `Evidence-based articles about ${tagName.toLowerCase()} from the LogYourBody team. Science-backed content on body composition and fitness.`,
    openGraph: {
      title: `${tagName} Articles - LogYourBody Blog`,
      description: `Evidence-based articles about ${tagName.toLowerCase()}.`,
      type: 'website',
    },
  };
}

export default async function TagPage({ params }: TagPageProps) {
  const { tag } = await params;
  // Convert URL tag back to display format
  const tagName = tag.replace(/-/g, ' ').replace(/\b\w/g, l => l.toUpperCase());
  
  // Get all tags to find the exact match
  const allTags = await getAllTags();
  const exactTag = allTags.find(t => t.toLowerCase().replace(/\s+/g, '-') === tag);
  
  if (!exactTag) {
    notFound();
  }
  
  const posts = await getPostsByTag(exactTag);

  return (
    <div className="min-h-screen bg-linear-bg font-inter">
      <Header />
      
      {/* Tag Header */}
      <div className="border-b border-linear-border">
        <div className="container mx-auto px-4 sm:px-6 py-12">
          <Link href="/blog">
            <Button variant="ghost" className="text-linear-text-secondary hover:text-linear-text mb-6">
              <ArrowLeft className="h-4 w-4 mr-2" />
              Back to Blog
            </Button>
          </Link>
          
          <div className="max-w-3xl">
            <div className="mb-4">
              <Badge className="bg-linear-purple/10 text-linear-purple border-linear-purple/20 text-lg px-4 py-2">
                {exactTag}
              </Badge>
            </div>
            <h1 className="text-4xl sm:text-5xl font-bold tracking-tight text-linear-text mb-4">
              {tagName} Articles
            </h1>
            <p className="text-lg text-linear-text-secondary leading-relaxed">
              Evidence-based content about {tagName.toLowerCase()}. Backed by research, tested in practice.
            </p>
          </div>
        </div>
      </div>

      <div className="container mx-auto px-4 sm:px-6 py-12">
        {posts.length === 0 ? (
          <div className="text-center py-12">
            <p className="text-linear-text-secondary">No articles found for this topic.</p>
            <Link href="/blog">
              <Button variant="outline" className="mt-4 border-linear-border text-linear-text-secondary hover:bg-linear-border/30">
                Browse All Articles
              </Button>
            </Link>
          </div>
        ) : (
          <div className="max-w-4xl mx-auto space-y-8">
            {posts.map((post) => (
              <Card 
                key={post.slug}
                className="border-linear-border bg-linear-card hover:bg-linear-card/80 transition-colors"
              >
                <CardHeader>
                  <div className="flex flex-wrap items-center gap-2 mb-3">
                    {post.tags.map((tag) => (
                      <Badge 
                        key={tag}
                        variant="secondary"
                        className={
                          tag === exactTag 
                            ? "bg-linear-purple/20 text-linear-purple border-linear-purple/30"
                            : "bg-linear-purple/10 text-linear-purple border-linear-purple/20"
                        }
                      >
                        {tag}
                      </Badge>
                    ))}
                  </div>
                  <CardTitle className="text-linear-text hover:text-linear-purple transition-colors">
                    <Link href={`/blog/${post.slug}`}>
                      {post.title}
                    </Link>
                  </CardTitle>
                  <div className="flex items-center gap-4 text-sm text-linear-text-tertiary">
                    <div className="flex items-center gap-1">
                      <User className="h-4 w-4" />
                      {post.author}
                    </div>
                    <div className="flex items-center gap-1">
                      <Calendar className="h-4 w-4" />
                      {post.formattedDate}
                    </div>
                    <div className="flex items-center gap-1">
                      <Clock className="h-4 w-4" />
                      {post.readTime}
                    </div>
                  </div>
                </CardHeader>
                <CardContent>
                  <CardDescription className="text-linear-text-secondary leading-relaxed">
                    {post.excerpt}
                  </CardDescription>
                  <Link 
                    href={`/blog/${post.slug}`}
                    className="inline-flex items-center mt-4 text-linear-purple hover:text-linear-purple/80 transition-colors font-medium"
                  >
                    Read more →
                  </Link>
                </CardContent>
              </Card>
            ))}
          </div>
        )}
      </div>
      
      <Footer />
    </div>
  );
}