# BMJ AI Rapid Prototype - Vercel Deployment Guide

This guide will walk you through deploying your BMJ-styled hello world page to Vercel.

## 📋 Prerequisites

Before you begin, ensure you have:

- A [GitHub](https://github.com) account
- A [Vercel](https://vercel.com) account (you can sign up with GitHub)
- Git installed on your local machine
- The BMJ pattern library in your repository

## 🚀 Quick Start Deployment

### Option 1: Deploy via Vercel CLI (Fastest)

1. **Install Vercel CLI**
   ```bash
   npm install -g vercel
   ```

2. **Navigate to your project directory**
   ```bash
   cd /Users/imulvany/Documents/GitHub/claude-skills-example/example_vercel_deploy/bmj-ai-rapid-prototype
   ```

3. **Deploy to Vercel**
   ```bash
   vercel
   ```

4. **Follow the prompts**
   - Login to your Vercel account
   - Confirm project settings
   - Your site will be deployed and you'll get a URL!

### Option 2: Deploy via Vercel Dashboard (Recommended)

#### Step 1: Initialize Git Repository (if not already done)

```bash
cd /Users/imulvany/Documents/GitHub/claude-skills-example
git init
git add .
git commit -m "Initial commit: BMJ AI Rapid Prototype"
```

#### Step 2: Push to GitHub

1. Create a new repository on GitHub
   - Go to https://github.com/new
   - Name it `claude-skills-example` or similar
   - Don't initialize with README (since you already have files)

2. Push your code:
   ```bash
   git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git
   git branch -M main
   git push -u origin main
   ```

#### Step 3: Deploy on Vercel

1. **Go to [Vercel Dashboard](https://vercel.com/dashboard)**

2. **Click "Add New Project"**

3. **Import your GitHub repository**
   - Select the repository you just created
   - Click "Import"

4. **Configure Project Settings**
   - **Framework Preset:** Other
   - **Root Directory:** `example_vercel_deploy/bmj-ai-rapid-prototype`
   - **Build Command:** (leave empty - static site)
   - **Output Directory:** (leave empty - will use root)

5. **Deploy!**
   - Click "Deploy"
   - Wait 30-60 seconds
   - Your site is live! 🎉

## 📁 Project Structure

```
bmj-ai-rapid-prototype/
├── index.html           # Main HTML page with BMJ header & footer
├── app.js              # Vanilla JavaScript for interactivity
├── vercel.json         # Vercel configuration
├── DEPLOYMENT_GUIDE.md # This file
└── (links to)
    └── ../../bmj-pat-lib/  # BMJ Pattern Library
        ├── assets/css/
        │   ├── bmj-base.css
        │   └── bmj-typography.css
        └── components/
            ├── header/
            ├── footer/
            ├── buttons/
            └── cards/
```

## ⚙️ Configuration Files

### vercel.json

The `vercel.json` file configures how Vercel builds and serves your site:

```json
{
  "version": 2,
  "name": "bmj-ai-rapid-prototype",
  "builds": [
    {
      "src": "index.html",
      "use": "@vercel/static"
    }
  ],
  "routes": [
    {
      "src": "/(.*)",
      "dest": "/$1"
    }
  ],
  "trailingSlash": false,
  "cleanUrls": true
}
```

**What this does:**
- Serves static HTML files
- Handles routing for clean URLs
- Removes trailing slashes
- No build process needed

## 🔧 Customization

### Adding Custom Domain

1. Go to your project in Vercel Dashboard
2. Click "Settings" → "Domains"
3. Add your custom domain
4. Follow DNS configuration instructions

### Environment Variables (for future enhancements)

If you need to add environment variables:

1. Go to "Settings" → "Environment Variables"
2. Add your variables:
   - `API_KEY`
   - `API_ENDPOINT`
   - etc.

### Updating the Deployment

After making changes:

```bash
git add .
git commit -m "Update: description of changes"
git push
```

Vercel automatically redeploys on every push to main branch!

## 🎨 Features Included

### ✅ BMJ Design System
- Full BMJ header with navigation
- Complete BMJ footer with links
- BMJ color palette and typography
- Responsive grid system

### ✅ Components
- Hero section with gradient background
- Welcome card with project information
- Feature cards showcasing capabilities
- Technical stack card

### ✅ Responsive Design
- Mobile-first approach
- Works on all device sizes
- Touch-friendly navigation

### ✅ Performance
- Static HTML (lightning fast)
- Minimal JavaScript
- Optimized CSS from pattern library

## 🐛 Troubleshooting

### CSS not loading?

**Issue:** The BMJ styles aren't appearing.

**Solution:** Ensure the `bmj-pat-lib` directory is in your repository at the correct path:
```
claude-skills-example/
├── bmj-pat-lib/          ← Must be here
└── example_vercel_deploy/
    └── bmj-ai-rapid-prototype/
        └── index.html    ← References ../../bmj-pat-lib/
```

### 404 errors on deployment?

**Issue:** Getting 404 errors on Vercel.

**Solution:** Check your Root Directory setting in Vercel:
- Should be: `example_vercel_deploy/bmj-ai-rapid-prototype`
- Verify in Project Settings → General

### Assets not loading?

**Issue:** Images, fonts, or other assets not loading.

**Solution:**
1. Ensure all paths are relative
2. Check that files are committed to Git
3. Verify file permissions

## 📊 Monitoring & Analytics

### View Deployment Status

- **Dashboard:** https://vercel.com/dashboard
- **Real-time logs:** Click on your deployment → "Logs"
- **Performance:** Built-in analytics available

### Enable Vercel Analytics

1. Go to your project settings
2. Navigate to "Analytics"
3. Enable Web Analytics (free for hobby projects)

## 🔐 Security Best Practices

### HTTPS
- Vercel provides free SSL certificates automatically
- All traffic is encrypted by default

### Headers
Add security headers in `vercel.json`:

```json
{
  "headers": [
    {
      "source": "/(.*)",
      "headers": [
        {
          "key": "X-Content-Type-Options",
          "value": "nosniff"
        },
        {
          "key": "X-Frame-Options",
          "value": "DENY"
        },
        {
          "key": "X-XSS-Protection",
          "value": "1; mode=block"
        }
      ]
    }
  ]
}
```

## 🚀 Next Steps

### Add Backend Functionality

When you're ready to add server-side functionality:

1. **Vercel Serverless Functions**
   - Create `/api` directory
   - Add Node.js functions
   - Example: `/api/hello.js`

2. **Database Integration**
   - Connect to Vercel Postgres
   - Or use external database (MongoDB, Supabase, etc.)

3. **Authentication**
   - Add Auth0, NextAuth, or similar
   - Protect routes with middleware

### Enhance the Frontend

1. **Add more pages**
   - Create additional HTML files
   - Link them in navigation

2. **Add interactivity**
   - Expand `app.js` with more features
   - Add form submissions
   - Implement search functionality

3. **Use BMJ Components**
   - Explore `bmj-pat-lib/components/`
   - Add forms, cards, buttons
   - Follow BMJ design patterns

## 📚 Resources

### Vercel Documentation
- [Vercel Docs](https://vercel.com/docs)
- [Static Sites Guide](https://vercel.com/docs/concepts/projects/overview)
- [Custom Domains](https://vercel.com/docs/concepts/projects/domains)

### BMJ Pattern Library
- Location: `../../bmj-pat-lib/`
- README: `../../bmj-pat-lib/README.md`
- Examples: `../../bmj-pat-lib/index.html`

### Git & GitHub
- [GitHub Docs](https://docs.github.com)
- [Git Basics](https://git-scm.com/book/en/v2/Getting-Started-Git-Basics)

## 🆘 Support

### Getting Help

1. **Vercel Community:** https://vercel.com/community
2. **GitHub Issues:** Create an issue in your repository
3. **Vercel Support:** support@vercel.com (Pro/Enterprise)

## ✨ Summary

Your BMJ AI Rapid Prototype is now ready for deployment!

**What you have:**
- ✅ Complete BMJ-styled HTML page
- ✅ Full navigation header and footer
- ✅ Responsive design
- ✅ Vercel configuration
- ✅ Vanilla HTML/CSS/JS (no build process needed)

**To deploy:**
```bash
# Option 1: Vercel CLI
vercel

# Option 2: Push to GitHub, then import in Vercel Dashboard
git push origin main
```

**Your site will be live at:**
```
https://your-project-name.vercel.app
```

Happy deploying! 🚀
