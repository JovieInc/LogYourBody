import { promises as fs } from 'fs';
import path from 'path';
import { logYourBody } from '@jovieinc/product-registry';

export type LegalDocumentType = 'privacy' | 'terms' | 'health';

const documentMap: Record<LegalDocumentType, string> = {
  privacy: 'privacy-policy.md',
  terms: 'terms-of-service.md',
  health: 'health-disclosure.md',
};

/**
 * Load a legal document from the shared legal directory
 * This function should only be called from server components
 */
export async function loadLegalDocument(type: LegalDocumentType): Promise<string> {
  try {
    // Path to shared legal documents (go up from apps/web to root)
    const docPath = path.join(process.cwd(), '..', '..', 'shared', 'legal', documentMap[type]);

    // Read the markdown file
    const content = await fs.readFile(docPath, 'utf-8');

    return content;
  } catch (error) {
    console.error(`Failed to load legal document ${type}:`, error);

    // Fallback content
    const fallbackContent: Record<LegalDocumentType, string> = {
      privacy: `# Privacy Policy

**Last Updated: ${new Date().toLocaleDateString()}**

We are committed to protecting your privacy. Please check back soon for our full privacy policy.

For questions, contact: ${logYourBody.contacts.privacy}`,

      terms: `# Terms of Service

**Last Updated: ${new Date().toLocaleDateString()}**

By using LogYourBody, you agree to our terms. Please check back soon for our full terms of service.

For questions, contact: ${logYourBody.contacts.legal}`,

      health: `# Health Disclosure

**Last Updated: ${new Date().toLocaleDateString()}**

LogYourBody is not a medical service. Please check back soon for our full health disclosure.

Always consult with healthcare professionals for medical advice.`,
    };

    return fallbackContent[type];
  }
}
