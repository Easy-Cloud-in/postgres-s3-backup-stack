# Initialize with main branch
git init --initial-branch=main

# Add your .gitignore first
git add .gitignore

# Initial commit with .gitignore
git commit -m "Initial commit: Add .gitignore"

# Now add remaining files
git add .

# Commit your project files
git commit -m "postgres-docker-setup-with-backup-solution-to-aws-s3"

# If you need to add a remote repository
# git remote add origin <your-repository-url>
# git branch -M main
# git push -u origin main