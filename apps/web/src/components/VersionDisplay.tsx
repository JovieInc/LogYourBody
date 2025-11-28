'use client';

import React, { useMemo } from 'react';
import { Badge } from '@shared-ui/atoms/badge';

interface VersionDisplayProps {
  className?: string;
  showBuildInfo?: boolean;
}

export const VersionDisplay = React.memo(function VersionDisplay({
  className = '',
}: VersionDisplayProps) {
  const versionInfo = useMemo(
    () => ({
      version: process.env.NEXT_PUBLIC_VERSION || process.env.NEXT_PUBLIC_APP_VERSION || '1.0.0',
    }),
    [],
  );

  return (
    <Badge
      variant="outline"
      className={`border-linear-border text-linear-text-tertiary text-xs opacity-50 ${className}`}
    >
      v{versionInfo.version}
    </Badge>
  );
});
