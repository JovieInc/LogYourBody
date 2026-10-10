# Include the two heartbeat scripts despite SimpleCov's default hidden-file filter.
SimpleCov.configure do
  filters.clear
  skip do |file|
    !file.filename.end_with?('/.github/scripts/await-runner-heartbeat.sh', '/.github/scripts/query-runner-heartbeat.sh')
  end
  cover '.github/scripts/{await,query}-runner-heartbeat.sh'
  coverage_dir 'coverage/mac-runner-routing'
  coverage(:line) { minimum 80, per: :file }
end
