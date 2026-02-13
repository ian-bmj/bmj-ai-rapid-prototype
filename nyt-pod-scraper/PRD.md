Read the article to get a sense of how a pod scraping app can help a journalisim org. 

Look at the png file to get an overvew of the kind of AWS architecture we are comfortable with at BMJ.

Plan to create:

- a SPA (single page application) that can be served from a static website hosting service like AWS S3.
- It will allow the editorial team to:
    - list or delist podcasts
    - view the podcast details
    - view podcast transcripts, summaries, gists, and themese
    - manage the daily and weekly email distribution lists of the summary email 
    - have auth managed by AWS Cognito
    - any config should be stored in S3 

- Back end should scrape audio and
 - store audio in S3 
 - store a transcript of the audio in S3
 - run transcrip through an LLM to generate a summary, gist, and themes
 - on a daily and weekly basis run these summaries across podcasts to create a daily and weekly summary email looking for overall themese
 - write a summariseing email that can be sent to the distribution list and emial handler. 

 
You need to arcitect the above, and create a plan for the implementation, and terraform file.

Potentially use the strands python API for back end work involving LLMs

I also want to test locally, so you need to create a local development environment that can be used to test the application.

I will not be providing AWS keys in hte first instance, so the AWS infrastructure work in this instnace is for planning and review purposes only, but you can create a local development environment that can be used to test the application.

# Local Specifics

Thnk carefull about how to test localy vs in AWS, are there good mocking services that mock the S3 APi but use the local filesystem? 

Likewiser Rather than using Cognito for LLM access locally you can create a python glue script that we can pass an LLM key for either GPT or Claude or Gemini to?  

I am particuarly interested locally in refining the admin app, and the text and format of the emails, The back end architecture can be refined later. 

# Show and tell

The repo you are working in has a github pages turned on e.g. https://ian-bmj.github.io/bmj-ai-rapid-prototype/tutorial/pyodide-wasm-tutorial.html, after doing the above work, create a site that can be served in GHPages that gives a nice outline of what you are aiming for, what you have done so far, and provides architectural diagrams of what has either been done, or is planned. 