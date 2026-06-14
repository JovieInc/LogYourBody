const React = require('react');

function createIcon(name) {
  return function Icon(props) {
    return React.createElement('svg', { 'data-icon': name, ...props });
  };
}

const icons = {
  // Navigation / layout
  Home: createIcon('Home'),
  Plus: createIcon('Plus'),
  Settings: createIcon('Settings'),
  Menu: createIcon('Menu'),
  PanelLeft: createIcon('PanelLeft'),

  // Status & actions
  X: createIcon('X'),
  Share: createIcon('Share'),
  RefreshCw: createIcon('RefreshCw'),
  CloudOff: createIcon('CloudOff'),
  CloudUpload: createIcon('CloudUpload'),
  Cloud: createIcon('Cloud'),
  AlertCircle: createIcon('AlertCircle'),
  Loader2: createIcon('Loader2'),
  Check: createIcon('Check'),
  CheckCircle: createIcon('CheckCircle'),
  CheckCircle2: createIcon('CheckCircle2'),

  // Time / date
  Calendar: createIcon('Calendar'),
  Clock: createIcon('Clock'),
  Clock3: createIcon('Clock3'),
  ChevronLeft: createIcon('ChevronLeft'),
  ChevronRight: createIcon('ChevronRight'),
  ChevronDown: createIcon('ChevronDown'),
  ChevronUp: createIcon('ChevronUp'),
  MoreHorizontal: createIcon('MoreHorizontal'),

  // Auth / phone
  Apple: createIcon('Apple'),
  Smartphone: createIcon('Smartphone'),

  // Metrics / charts / misc
  BarChart3: createIcon('BarChart3'),
  Camera: createIcon('Camera'),
  TrendingUp: createIcon('TrendingUp'),
  TrendingDown: createIcon('TrendingDown'),
  Activity: createIcon('Activity'),
  Dumbbell: createIcon('Dumbbell'),
  Footprints: createIcon('Footprints'),
  HeartPulse: createIcon('HeartPulse'),
  LockKeyhole: createIcon('LockKeyhole'),
  Ruler: createIcon('Ruler'),
  Zap: createIcon('Zap'),
  Tablet: createIcon('Tablet'),
  Watch: createIcon('Watch'),
  Download: createIcon('Download'),
  ArrowRight: createIcon('ArrowRight'),
  Sparkles: createIcon('Sparkles'),
  Shield: createIcon('Shield'),
  Wifi: createIcon('Wifi'),
  WifiOff: createIcon('WifiOff'),
  Eye: createIcon('Eye'),
  EyeOff: createIcon('EyeOff'),
  Search: createIcon('Search'),
  Circle: createIcon('Circle'),
  GripVertical: createIcon('GripVertical'),
};

module.exports = icons;
