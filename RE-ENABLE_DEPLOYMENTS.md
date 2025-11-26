# Re-enabling Deployments After Configuring Secrets

Once you've configured the Clerk secrets in the appropriate GitHub environments, you can re-enable deployments.

## Steps to Re-enable Web Rapid Loop Deployment

1. **Verify secrets are configured**:
   ```bash
   # Check development environment has Clerk secrets
   gh api repos/JovieInc/LogYourBody/environments/development/secrets --jq '.secrets[].name' | grep CLERK
   ```

2. **Edit the web-rapid-loop.yml file**:
   
   Open `.github/workflows/web-rapid-loop.yml` and uncomment the entire `deploy-alpha` job (lines 67-129).
   
   Change from:
   ```yaml
   # TODO: Re-enable once Clerk secrets are configured
   # deploy-alpha:
   #   name: Deploy to Vercel Alpha
   #   ...
   ```
   
   To:
   ```yaml
   deploy-alpha:
     name: Deploy to Vercel Alpha
     needs: rapid-checks
     runs-on: ubuntu-latest
     timeout-minutes: 5
     environment:
       name: development
       url: ${{ steps.deploy.outputs.url }}
     
     steps:
     - uses: actions/checkout@v4
     # ... rest of the job
   ```

3. **Re-enable tests** (optional):
   
   If you want to re-enable unit tests, also uncomment in the rapid-checks job:
   ```yaml
   npm run test &
   TEST_PID=$!
   # ...
   wait $TEST_PID || (echo "❌ Unit tests failed" && exit 1)
   ```

4. **Commit and push**:
   ```bash
   git add .github/workflows/web-rapid-loop.yml
   git commit -m "fix: re-enable web deployment after configuring Clerk secrets"
   git push origin dev
   ```

## Verification

After pushing, check that:
1. The Web Rapid Loop workflow runs successfully
2. The deployment step completes
3. You get a deployment URL in the workflow output

## Other Environments

Similar steps apply for:
- **preview** environment → web-confidence-loop.yml
- **production** environment → web-release-loop.yml

Make sure each environment has its appropriate Clerk keys configured before enabling deployments.