# LogYourBody MVP Launch Priority Tasks

**Status**: Ready for immediate execution  
**Last Updated**: September 3, 2025  
**Estimated Total Time**: 10-15 hours for critical path

## 🚨 PHASE 1: CRITICAL BLOCKERS (1-2 days)

### iOS App Store Blockers
**Total Time**: 4-5 hours | **Impact**: Prevents App Store submission

#### Task 1.1: Fix Info.plist Permissions (30 minutes)
**File**: `apps/ios/LogYourBody/Info.plist`
```xml
<!-- Add these entries -->
<key>NSPhotoLibraryUsageDescription</key>
<string>LogYourBody needs access to your photo library to let you select progress photos.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>LogYourBody needs to save your progress photos to your photo library.</string>
<key>LSApplicationCategoryType</key>
<string>public.app-category.health-fitness</string>
```

#### Task 1.2: Synchronize Version Numbers (15 minutes)
**Files to update**:
- `apps/ios/LogYourBody/Info.plist`: CFBundleShortVersionString → "1.2.0"
- `apps/ios/LogYourBody/Constants.swift`: version → "1.2.0"
- Generate build number using timestamp format

#### Task 1.3: Remove Fatal Errors (2 hours)
**Priority**: HIGH - Prevents app crashes
**Files to fix**:
- `apps/ios/LogYourBody/CoreDataManager.swift:15`
- `apps/ios/LogYourBody/AuthManager.swift:1548`  
- `apps/ios/LogYourBody/AppleSignInButton.swift:107`

Replace `fatalError()` with:
```swift
// Instead of fatalError()
logger.error("Critical error: \(error)")
// Handle gracefully or show user error
```

#### Task 1.4: Clean Debug Code (1 hour)
**Scope**: Remove 200+ print statements
**Action**:
```swift
// Wrap debug code
#if DEBUG
print("Debug message")
#endif
```
**Files**: All .swift files with print statements

### Web App Critical Fixes
**Total Time**: 8-10 hours | **Impact**: Core functionality broken

#### Task 1.5: Fix Test Suite Failures (6 hours)
**Priority**: CRITICAL - 114/233 tests failing
**Focus Areas**:
1. Dashboard component import/export issues
2. Authentication context integration 
3. Profile settings test timeouts
4. Mock data inconsistencies

**Commands to run**:
```bash
cd apps/web
npm test -- --verbose
npm run test:coverage
```

#### Task 1.6: Security Vulnerability Patches (2 hours)
**Action**:
```bash
cd apps/web
npm audit fix
npm update next@15.5.2
# Review and update vulnerable packages
```

**Critical vulnerabilities**:
- xlsx library (Prototype pollution) - HIGH
- Next.js content injection - MODERATE
- PrismJS DOM clobbering - MODERATE

## 🔥 PHASE 2: HIGH PRIORITY (1 week)

### iOS App Store Preparation
**Total Time**: 8-12 hours | **Impact**: Required for submission

#### Task 2.1: Create App Store Assets (4 hours)
- [ ] Screenshots for iPhone 6.5" (iPhone 14 Pro Max)
- [ ] Screenshots for iPhone 5.5" (iPhone 8 Plus)
- [ ] App Store description (focus on privacy & health)
- [ ] Keywords: "body composition, weight tracker, progress photos, FFMI"
- [ ] App Preview video (optional, recommended)

#### Task 2.2: Final iOS Testing (3 hours)
**Test Scenarios**:
- [ ] Complete onboarding flow
- [ ] Log weight, body fat, and photo
- [ ] Test HealthKit sync
- [ ] Test Apple Sign In
- [ ] Test data export
- [ ] Test account deletion
- [ ] Verify offline functionality
- [ ] Check all external links work

#### Task 2.3: Type Safety Improvements (4 hours)
**Web App Focus**:
- Replace 100+ TypeScript `any` types
- Add proper interface definitions
- Fix React hook dependency warnings

### Web Component Architecture
**Total Time**: 6-8 hours | **Impact**: Core stability

#### Task 2.4: Dashboard Component Fixes (3 hours)
**Issues**:
- Component import/export resolution
- Authentication provider integration
- UI rendering consistency

#### Task 2.5: Error Handling Standardization (3 hours)
- Implement error boundaries
- Add network failure recovery
- Create user-friendly error messages

## ⚠️ PHASE 3: MEDIUM PRIORITY (2-4 weeks)

### Performance & Optimization
**Total Time**: 20-30 hours | **Impact**: User experience

#### Task 3.1: Memory Optimization (8 hours)
- Optimize photo upload handling
- Fix potential memory leaks
- Improve Core Data queries

#### Task 3.2: CI/CD Simplification (12 hours)
- Reduce workflow complexity
- Streamline deployment process
- Improve error reporting

#### Task 3.3: Documentation Consolidation (6 hours)
- Reduce 1625+ markdown files
- Create developer onboarding guide
- Standardize documentation format

### API & Integration Improvements
**Total Time**: 15-20 hours | **Impact**: Developer experience

#### Task 3.4: API Consistency (10 hours)
- Standardize endpoint patterns
- Improve error response formats
- Add comprehensive API docs

#### Task 3.5: Enhanced Testing (8 hours)
- Increase test coverage to >80%
- Add integration test suite
- Implement visual regression testing

## 📋 PHASE 4: NICE TO HAVE (1-3 months)

### Advanced Features
- Analytics integration
- Performance monitoring
- Advanced user insights
- Automated security scanning

### Developer Experience
- Automated environment setup
- Better debugging tools
- Hot reloading improvements

## Implementation Strategy

### Week 1: Critical Path
**Days 1-2**: iOS Critical Blockers (Tasks 1.1-1.4)
**Days 3-4**: Web Critical Fixes (Tasks 1.5-1.6)
**Day 5**: Testing and validation

### Week 2: High Priority
**Days 1-3**: iOS App Store Preparation (Tasks 2.1-2.2)
**Days 4-5**: Web Architecture Fixes (Tasks 2.4-2.5)

### Weeks 3-6: Medium Priority
Progressive implementation of Phase 3 tasks based on user feedback and monitoring data.

## Success Criteria

### Phase 1 Complete
- [ ] iOS app builds without errors
- [ ] All fatal errors removed
- [ ] Web test success rate >90%
- [ ] No high/critical security vulnerabilities

### Phase 2 Complete  
- [ ] iOS app ready for App Store submission
- [ ] Web app core functionality stable
- [ ] TypeScript errors <10
- [ ] All critical user journeys working

### Phase 3 Complete
- [ ] Test coverage >80%
- [ ] Performance metrics within targets
- [ ] CI/CD simplified and stable
- [ ] Documentation consolidated

## Risk Mitigation

### High Risk Items
1. **iOS App Store rejection**: Address all blockers before submission
2. **Web app instability**: Focus on test suite first
3. **Timeline pressure**: Prioritize critical path ruthlessly

### Contingency Plans
- **iOS delays**: Submit with minimum viable fixes, iterate post-approval
- **Web issues**: Launch iOS first, delay web launch if needed
- **Resource constraints**: Focus on single platform for MVP

## Team Allocation Recommendations

### Immediate (Phase 1)
- **iOS Developer**: Focus on critical blockers (Tasks 1.1-1.4)
- **Web Developer**: Fix test suite and security issues (Tasks 1.5-1.6)
- **QA**: Validation and testing support

### Near-term (Phase 2)
- **iOS Developer**: App Store assets and final testing
- **Web Developer**: Component architecture and type safety
- **Designer**: App Store screenshots and marketing materials

This priority list provides a clear roadmap for achieving MVP launch readiness within 2 weeks, with focus on the most critical issues first.