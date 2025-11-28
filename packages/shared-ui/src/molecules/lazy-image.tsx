import React, { useState, useRef, useEffect } from 'react';
import { cn } from '@shared-lib/utils';

interface LazyImageProps extends React.ImgHTMLAttributes<HTMLImageElement> {
  src: string;
  alt: string;
  srcSet?: string;
  sizes?: string;
  placeholder?: string;
  className?: string;
  fallback?: React.ReactNode;
}

export const LazyImage = React.memo(function LazyImage({
  src,
  alt,
  srcSet,
  sizes,
  placeholder = '/placeholder.svg',
  className,
  fallback,
  ...props
}: LazyImageProps) {
  const [isLoaded, setIsLoaded] = useState(false);
  const [isInView, setIsInView] = useState(false);
  const [hasError, setHasError] = useState(false);
  const imgRef = useRef<HTMLImageElement>(null);

  useEffect(() => {
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setIsInView(true);
          observer.disconnect();
        }
      },
      { threshold: 0.1 },
    );

    if (imgRef.current) {
      observer.observe(imgRef.current);
    }

    return () => observer.disconnect();
  }, []);

  const handleLoad = () => {
    setIsLoaded(true);
    setHasError(false);
  };

  const handleError = () => {
    setHasError(true);
    setIsLoaded(false);
  };

  if (hasError && fallback) {
    return <>{fallback}</>;
  }

  return (
    <div ref={imgRef} className={cn('relative overflow-hidden', className)}>
      {/* Placeholder */}
      {!isLoaded && placeholder && (
        <img
          src={placeholder}
          alt=""
          className={cn(
            'absolute inset-0 h-full w-full object-cover transition-opacity duration-300',
            isLoaded ? 'opacity-0' : 'opacity-100',
          )}
          aria-hidden="true"
        />
      )}

      {/* Loading shimmer */}
      {!isLoaded && isInView && (
        <div className="absolute inset-0 animate-pulse bg-gradient-to-r from-transparent via-white/20 to-transparent" />
      )}

      {/* Actual image */}
      {isInView && (
        <img
          src={src}
          srcSet={srcSet}
          sizes={sizes}
          alt={alt}
          onLoad={handleLoad}
          onError={handleError}
          className={cn(
            'h-full w-full object-cover transition-opacity duration-300',
            isLoaded ? 'opacity-100' : 'opacity-0',
          )}
          loading="lazy"
          {...props}
        />
      )}
    </div>
  );
});
