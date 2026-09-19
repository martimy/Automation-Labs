---
output: pdf_document
geometry: margin=1in
title: GitHub Access Token Setup
subtitle: INWK6312 Fall26/27
---

Follow these steps to setup an access token needed to authenticate access to GitHub repository.

1. Open the Classroom 50 assignment link:  
    Open the assignment link provided by your instructor's email. If this is your first lab, accept it to generate your personal remote repository for this course. If you already accepted it in a previous lab, use your existing repository — do not accept the link again or create a second one.

2. Go to GitHub's fine-grained token settings:  
    In a browser, sign in to GitHub and go to `Settings → Developer settings → Personal access tokens → Fine-grained tokens` (or go directly to github.com/settings/tokens?type=beta). Click "Generate new token."

3. Name the token and set an expiration:  
    Give it a descriptive name, e.g. `inwk6312-labs-token`, so you can recognize it later if you need to revoke or regenerate it. Set an expiration date that covers the rest of the course (~60 days).

4. Set the resource owner to the course organization:  
    Under "Resource owner," select the course's GitHub organization (not your personal account). If the organization doesn't appear as an option, your token request may need approval enabled by the organization owner; contact your instructor.

5. Limit access to only your own repository:  
    Under "Repository access," choose "Only select repositories" and select your own assignment repository (named  `inwk6312-fall2627-labs-<your-username>`). Do not select "All repositories".

6. Set the required repository permissions:  
    Scroll to "Repository permissions" and set the following to Read and write (leave everything else its default): Actions, Contents, and Workflows

7. Generate and copy the token immediately:  
    Click "Generate token" at the bottom of the page. GitHub shows the token value exactly once. Copy the token now and store it somewhere safe. If you navigate away before copying it, you'll need to generate a new one.

8. Use the token as your password when pushing:  
    When Git prompts for a username and password during git push (or any HTTPS Git operation), enter your GitHub username as the username and paste the token as the password. Your regular GitHub account password will not work.