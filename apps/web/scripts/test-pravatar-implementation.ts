#!/usr/bin/env tsx

import { 
  getPravatarUrl, 
  getUserAvatarUrl, 
  getRandomAvatarUrl, 
  getAvatarByImageId,
  getProfileAvatarUrl 
} from '../src/utils/pravatar-utils'

console.log('🧪 Testing Pravatar Implementation\n')
console.log('=' .repeat(50))

// Test 1: Basic URL generation
console.log('\n1. Basic Pravatar URL (default size):')
const basicUrl = getPravatarUrl()
console.log(`   ${basicUrl}`)

// Test 2: Custom size
console.log('\n2. Custom size (500px):')
const customSizeUrl = getPravatarUrl({ size: 500 })
console.log(`   ${customSizeUrl}`)

// Test 3: Specific image ID
console.log('\n3. Specific image ID (ID: 42):')
const specificImageUrl = getAvatarByImageId(42, 200)
console.log(`   ${specificImageUrl}`)

// Test 4: User-specific avatar (consistent)
console.log('\n4. User-specific avatars (consistent per user):')
const users = ['sarah.chen@example.com', 'marcus.johnson@example.com', 'emily.rodriguez@example.com']
users.forEach(email => {
  const url = getUserAvatarUrl(email, 150)
  console.log(`   ${email}: ${url}`)
})

// Test 5: Random avatars
console.log('\n5. Random avatars (different each time):')
for (let i = 1; i <= 3; i++) {
  const url = getRandomAvatarUrl(150)
  console.log(`   Random ${i}: ${url}`)
}

// Test 6: Profile avatars (using username)
console.log('\n6. Profile avatars by username:')
const usernames = ['sarahc', 'marcusj', 'emilyr', 'davidk', 'jessicat']
usernames.forEach(username => {
  const url = getProfileAvatarUrl(username, 300)
  console.log(`   @${username}: ${url}`)
})

// Test 7: Progress photo avatars
console.log('\n7. Progress photo avatars (unique per photo):')
const photoScenarios = [
  { username: 'sarahc', date: '2024-01-15', angle: 'front' },
  { username: 'sarahc', date: '2024-01-15', angle: 'side' },
  { username: 'marcusj', date: '2024-06-01', angle: 'back' }
]
photoScenarios.forEach(({ username, date, angle }) => {
  const identifier = `${username}-${date}-${angle}`
  const photoUrl = getProfileAvatarUrl(identifier, 600)
  const thumbUrl = getProfileAvatarUrl(identifier, 150)
  console.log(`   ${identifier}:`)
  console.log(`     Photo: ${photoUrl}`)
  console.log(`     Thumb: ${thumbUrl}`)
})

// Test 8: Edge cases
console.log('\n8. Edge cases:')
console.log('   Max size (1000px):')
console.log(`     ${getPravatarUrl({ size: 1500 })} (should clamp to 1000)`)
console.log('   Special characters in identifier:')
console.log(`     ${getUserAvatarUrl('user+test@example.com', 150)}`)
console.log('   Image ID out of range:')
console.log(`     ${getAvatarByImageId(100, 150)} (should clamp to 70)`)
console.log(`     ${getAvatarByImageId(0, 150)} (should clamp to 1)`)

console.log('\n' + '=' .repeat(50))
console.log('✅ All tests completed!\n')

// Display migration instructions
console.log('📝 Migration Instructions:')
console.log('1. Add a reviewed SQL migration under apps/web/db/migrations when data changes are needed')
console.log('2. Apply it with a direct Neon connection: pnpm --filter logyourbody db:apply:neon')
console.log('3. New users will automatically get Pravatar URLs')
console.log('4. Existing DiceBear URLs can be updated through the first-party profile API\n')
