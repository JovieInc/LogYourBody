import { getAllPosts, getAllTags } from '@/lib/blog';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Header } from '@/components/Header';
import { Footer } from '@/components/Footer';
import Link from 'next/link';
import { Calendar, Clock, User } from 'lucide-react';
import { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Blog - LogYourBody',
  description: 'Evidence-based articles on body composition, muscle building, fat loss, and fitness science from the LogYourBody team.',
  openGraph: {
    title: 'Blog - LogYourBody',
    description: 'Evidence-based articles on body composition, muscle building, fat loss, and fitness science.',
    type: 'website',
  }
};

export default async function BlogPage() {
  const posts = await getAllPosts();
  const tags = await getAllTags();

  return (
    <div className="min-h-screen bg-linear-bg font-inter">
      <Header />
      
      {/* Hero Section */}
      <div className="border-b border-linear-border">
        <div className="container mx-auto px-4 sm:px-6 py-16">
          <div className="max-w-3xl">
            <h1 className="text-4xl sm:text-5xl font-bold tracking-tight text-linear-text mb-4">
              Evidence-Based Fitness
            </h1>
            <p className="text-lg text-linear-text-secondary leading-relaxed">
              Science-backed articles on body composition, muscle building, and sustainable fitness practices. 
              No BS, just research and real results.
            </p>
          </div>
        </div>
      </div>

      <div className="container mx-auto px-4 sm:px-6 py-12">
        <div className="grid gap-12 lg:grid-cols-4">
          {/* Main Content */}
          <div className="lg:col-span-3">
            {posts.length === 0 ? (
              <div className="text-center py-12">
                <p className="text-linear-text-secondary">No blog posts found.</p>
              </div>
            ) : (
              <div className="space-y-8">
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
                            className="bg-linear-purple/10 text-linear-purple border-linear-purple/20"
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

          {/* Sidebar */}
          <div className="lg:col-span-1">
            <div className="sticky top-8 space-y-8">
              {/* Tags */}
              <Card className="border-linear-border bg-linear-card">
                <CardHeader>
                  <CardTitle className="text-linear-text text-lg">Topics</CardTitle>
                </CardHeader>
                <CardContent>
                  <div className="flex flex-wrap gap-2">
                    {tags.map((tag) => (
                      <Link key={tag} href={`/blog/tag/${tag.toLowerCase().replace(/\s+/g, '-')}`}>
                        <Badge 
                          variant="outline"
                          className="border-linear-border text-linear-text-secondary hover:bg-linear-purple/10 hover:text-linear-purple hover:border-linear-purple/20 transition-colors cursor-pointer"
                        >
                          {tag}
                        </Badge>
                      </Link>
                    ))}
                  </div>
                </CardContent>
              </Card>

              {/* About */}
              <Card className="border-linear-border bg-linear-card">
                <CardHeader>
                  <CardTitle className="text-linear-text text-lg">About This Blog</CardTitle>
                </CardHeader>
                <CardContent>
                  <p className="text-sm text-linear-text-secondary leading-relaxed">
                    We cut through fitness industry noise with evidence-based content. 
                    Every article is backed by peer-reviewed research and real-world testing.
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