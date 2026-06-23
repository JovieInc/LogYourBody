// Blog utilities for loading and parsing markdown posts
import 'server-only';
import fs from 'fs';
import path from 'path';
import { load as loadYaml } from 'js-yaml';
import { getTeamMemberByName } from './team';

export interface BlogPost {
  slug: string;
  title: string;
  date: string;
  author: string;
  authorId?: string;
  authorRole?: string;
  authorStats?: {
    bodyFat: number;
  };
  tags: string[];
  excerpt: string;
  readTime: string;
  content: string;
  formattedDate: string;
}

type BlogFrontmatter = Partial<
  Pick<BlogPost, 'title' | 'date' | 'author' | 'excerpt'> & {
    tags: string[];
  }
>;

// Get the posts directory
const postsDirectory = path.join(process.cwd(), 'public/blog');

function parsePost(fileContents: string): { data: BlogFrontmatter; content: string } {
  if (!fileContents.startsWith('---')) {
    return { data: {}, content: fileContents };
  }

  const frontmatterEnd = fileContents.indexOf('\n---', 3);
  if (frontmatterEnd === -1) {
    return { data: {}, content: fileContents };
  }

  const rawFrontmatter = fileContents.slice(3, frontmatterEnd).trim();
  const content = fileContents.slice(frontmatterEnd + 4).replace(/^\s+/, '');
  const parsed = loadYaml(rawFrontmatter);
  const data = parsed && typeof parsed === 'object' ? (parsed as BlogFrontmatter) : {};

  return { data, content };
}

export async function getAllPosts(): Promise<BlogPost[]> {
  try {
    const fileNames = fs.readdirSync(postsDirectory).filter((name) => name.endsWith('.md'));

    const allPostsData = await Promise.all(
      fileNames.map(async (fileName) => {
        const slug = fileName.replace(/\.md$/, '');
        return await getPostBySlug(slug);
      }),
    );

    // Filter out null posts and sort by date
    return allPostsData
      .filter((post): post is BlogPost => post !== null)
      .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
  } catch (error) {
    console.error('Error reading blog posts:', error);
    return [];
  }
}

export async function getPostBySlug(slug: string): Promise<BlogPost | null> {
  try {
    const fullPath = path.join(postsDirectory, `${slug}.md`);

    if (!fs.existsSync(fullPath)) {
      return null;
    }

    const fileContents = fs.readFileSync(fullPath, 'utf8');
    const { data, content } = parsePost(fileContents);

    // Calculate read time (assuming 200 words per minute)
    const wordCount = content.split(/\s+/).length;
    const readTime = Math.ceil(wordCount / 200);

    // Generate excerpt from content if not provided
    const excerpt = data.excerpt || content.substring(0, 200).replace(/[#*`]/g, '') + '...';

    // Get author details from team data
    const authorName = data.author || 'LogYourBody Team';
    const teamMember = getTeamMemberByName(authorName);

    return {
      slug,
      title: data.title || slug.replace(/-/g, ' '),
      date: data.date || new Date().toISOString().split('T')[0],
      author: authorName,
      authorId: teamMember?.id,
      authorRole: teamMember?.role,
      authorStats: teamMember
        ? {
            bodyFat: teamMember.bodyStats.bodyFat,
          }
        : undefined,
      tags: data.tags || [],
      excerpt,
      readTime: `${readTime} min read`,
      content,
      formattedDate: new Date(data.date || new Date()).toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'long',
        day: 'numeric',
      }),
    };
  } catch (error) {
    console.error(`Error reading post ${slug}:`, error);
    return null;
  }
}

export async function getPostsByTag(tag: string): Promise<BlogPost[]> {
  const allPosts = await getAllPosts();
  return allPosts.filter((post) => post.tags.some((t) => t.toLowerCase() === tag.toLowerCase()));
}

export async function getAllTags(): Promise<string[]> {
  const allPosts = await getAllPosts();
  const tags = new Set<string>();

  allPosts.forEach((post) => {
    post.tags.forEach((tag) => tags.add(tag));
  });

  return Array.from(tags).sort();
}

export async function getAllSlugs(): Promise<string[]> {
  try {
    const fileNames = fs.readdirSync(postsDirectory).filter((name) => name.endsWith('.md'));
    return fileNames.map((fileName) => fileName.replace(/\.md$/, ''));
  } catch (error) {
    console.error('Error reading blog directory:', error);
    return [];
  }
}
