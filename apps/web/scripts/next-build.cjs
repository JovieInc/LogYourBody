const { spawnSync } = require('node:child_process')

const result = spawnSync('next', ['build'], {
  stdio: 'inherit',
  shell: process.platform === 'win32',
})

process.exit(result.status ?? 1)
