'use client';

import { useMemo } from 'react';
import { motion } from 'framer-motion';
import { Sparkles } from 'lucide-react';
import ReactMarkdown from 'react-markdown';
import { cn } from '@/lib/utils';
import type { AppResponse } from '@/types/conversation';

/**
 * Parse markdown content into sections based on h2 headers
 * Returns an array of { title, content } objects
 */
function parseMarkdownSections(content: string): { title: string | null; content: string }[] {
  const lines = content.split('\n');
  const sections: { title: string | null; content: string }[] = [];
  let currentSection: { title: string | null; content: string[] } = { title: null, content: [] };

  for (const line of lines) {
    // Check for ## headers (h2)
    const h2Match = line.match(/^##\s+(.+)$/);
    if (h2Match) {
      // Save previous section if it has content
      if (currentSection.content.length > 0 || currentSection.title) {
        sections.push({
          title: currentSection.title,
          content: currentSection.content.join('\n').trim(),
        });
      }
      // Start new section
      currentSection = { title: h2Match[1], content: [] };
    } else {
      currentSection.content.push(line);
    }
  }

  // Don't forget the last section
  if (currentSection.content.length > 0 || currentSection.title) {
    sections.push({
      title: currentSection.title,
      content: currentSection.content.join('\n').trim(),
    });
  }

  return sections;
}

interface AppSummaryCardProps {
  appResponse: AppResponse;
  className?: string;
}

export function AppSummaryCard({ appResponse, className }: AppSummaryCardProps) {
  // Parse content into sections
  const sections = useMemo(() => {
    return parseMarkdownSections(appResponse.content || '');
  }, [appResponse.content]);

  // Check if content has multiple sections (h2 headers)
  const hasMultipleSections = sections.length > 1 || (sections.length === 1 && sections[0].title);

  if (!appResponse.content) {
    return null;
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      className={cn(
        'noise-overlay p-4 rounded-xl',
        'bg-white/[0.02] border border-white/[0.06]',
        className
      )}
    >
      {/* App Header */}
      <div className="flex items-center gap-3 mb-3">
        <div className="w-8 h-8 rounded-lg bg-purple-primary/20 flex items-center justify-center">
          <Sparkles className="w-4 h-4 text-purple-primary" />
        </div>
        <div className="flex-1 min-w-0">
          <h4 className="text-sm font-medium text-text-primary truncate">
            Template Summary
          </h4>
          {appResponse.app_id && (
            <p className="text-xs text-text-tertiary truncate">
              {appResponse.app_id}
            </p>
          )}
        </div>
      </div>

      {/* Summary Content - Sectioned or Plain */}
      {hasMultipleSections ? (
        <div className="space-y-4">
          {sections.map((section, index) => (
            <div
              key={index}
              className="p-3 rounded-lg bg-gradient-to-b from-white/[0.06] to-white/[0.02] border border-white/[0.08]"
            >
              {section.title && (
                <h3 className="text-sm font-medium text-text-primary mb-2">
                  {section.title}
                </h3>
              )}
              {section.content && (
                <div className="text-sm text-text-secondary leading-relaxed prose prose-sm prose-invert max-w-none prose-p:my-3 prose-headings:text-text-primary prose-headings:font-medium prose-h3:text-xs prose-h3:mt-4 prose-h3:mb-2 prose-ul:my-3 prose-li:my-1.5 prose-strong:text-text-primary prose-code:text-purple-primary prose-code:bg-bg-quaternary prose-code:px-1 prose-code:py-0.5 prose-code:rounded">
                  <ReactMarkdown>{section.content}</ReactMarkdown>
                </div>
              )}
            </div>
          ))}
        </div>
      ) : (
        <div className="text-sm text-text-secondary leading-relaxed prose prose-sm prose-invert max-w-none prose-p:my-3 prose-headings:text-text-primary prose-headings:font-medium prose-h2:text-base prose-h2:mt-5 prose-h2:mb-3 prose-h3:text-sm prose-h3:mt-4 prose-h3:mb-2 prose-ul:my-3 prose-li:my-1.5 prose-strong:text-text-primary prose-code:text-purple-primary prose-code:bg-bg-quaternary prose-code:px-1 prose-code:py-0.5 prose-code:rounded">
          <ReactMarkdown>{appResponse.content}</ReactMarkdown>
        </div>
      )}
    </motion.div>
  );
}

/**
 * Loading skeleton for AppSummaryCard
 */
export function AppSummaryCardSkeleton() {
  return (
    <div className="p-4 rounded-xl bg-bg-tertiary border border-bg-quaternary/50 animate-pulse">
      <div className="flex items-center gap-3 mb-3">
        <div className="w-8 h-8 rounded-lg bg-bg-quaternary" />
        <div className="flex-1">
          <div className="h-4 w-24 bg-bg-quaternary rounded" />
        </div>
      </div>
      <div className="space-y-2">
        <div className="h-3 w-full bg-bg-quaternary rounded" />
        <div className="h-3 w-5/6 bg-bg-quaternary rounded" />
        <div className="h-3 w-4/6 bg-bg-quaternary rounded" />
      </div>
    </div>
  );
}
