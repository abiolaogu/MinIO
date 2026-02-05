#!/usr/bin/env python3
"""
Trend Hunter Agent - External Research Bot
Fetches trending topics from Hacker News and Dev.to, uses Claude to analyze them,
and creates GitHub issues for valuable ideas.
"""

import os
import json
from datetime import datetime
from typing import List, Dict, Optional
import requests
from anthropic import Anthropic

# API Configuration
HACKER_NEWS_TOP_STORIES_API = "https://hacker-news.firebaseio.com/v0/topstories.json"
HACKER_NEWS_ITEM_API = "https://hacker-news.firebaseio.com/v0/item/{}.json"
DEV_TO_API = "https://dev.to/api/articles"

# GitHub Configuration
GITHUB_API_URL = "https://api.github.com"
GITHUB_REPO = os.environ.get("GITHUB_REPOSITORY", "")


def fetch_hacker_news_stories(count: int = 10) -> List[Dict]:
    """
    Fetch top stories from Hacker News API.

    Args:
        count: Number of top stories to fetch

    Returns:
        List of story dictionaries with title, url, and score
    """
    print(f"📡 Fetching top {count} stories from Hacker News...")

    try:
        # Get top story IDs
        response = requests.get(HACKER_NEWS_TOP_STORIES_API, timeout=10)
        response.raise_for_status()
        story_ids = response.json()[:count]

        stories = []
        for story_id in story_ids:
            try:
                item_response = requests.get(
                    HACKER_NEWS_ITEM_API.format(story_id),
                    timeout=10
                )
                item_response.raise_for_status()
                item = item_response.json()

                if item and item.get('type') == 'story':
                    stories.append({
                        'title': item.get('title', 'No title'),
                        'url': item.get('url', f"https://news.ycombinator.com/item?id={story_id}"),
                        'score': item.get('score', 0),
                        'source': 'Hacker News'
                    })
            except Exception as e:
                print(f"   ⚠️  Error fetching story {story_id}: {e}")
                continue

        print(f"   ✓ Fetched {len(stories)} stories from Hacker News")
        return stories

    except Exception as e:
        print(f"   ✗ Error fetching from Hacker News: {e}")
        return []


def fetch_devto_articles(count: int = 10) -> List[Dict]:
    """
    Fetch top articles from Dev.to API filtered by relevant tags.

    Args:
        count: Number of articles to fetch

    Returns:
        List of article dictionaries with title, url, and tags
    """
    print(f"📡 Fetching top {count} articles from Dev.to...")

    try:
        # Fetch articles with relevant tags
        params = {
            'per_page': count,
            'top': 7,  # Top articles from last 7 days
            'tag': 'ai,saas,product'
        }

        response = requests.get(DEV_TO_API, params=params, timeout=10)
        response.raise_for_status()
        articles = response.json()

        stories = []
        for article in articles[:count]:
            stories.append({
                'title': article.get('title', 'No title'),
                'url': article.get('url', ''),
                'tags': article.get('tag_list', []),
                'positive_reactions_count': article.get('positive_reactions_count', 0),
                'source': 'Dev.to'
            })

        print(f"   ✓ Fetched {len(stories)} articles from Dev.to")
        return stories

    except Exception as e:
        print(f"   ✗ Error fetching from Dev.to: {e}")
        return []


def analyze_trends_with_claude(trends: List[Dict]) -> Optional[Dict]:
    """
    Send trends to Claude for analysis and idea extraction.

    Args:
        trends: List of trend items to analyze

    Returns:
        Dictionary with idea name and description, or None if no good ideas found
    """
    print("\n🤖 Analyzing trends with Claude...")

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("   ✗ Error: ANTHROPIC_API_KEY not found in environment")
        return None

    try:
        client = Anthropic(api_key=api_key)

        # Format trends for Claude
        trends_text = "\n\n".join([
            f"**{i+1}. {trend['title']}** (Source: {trend['source']})\n"
            f"URL: {trend['url']}"
            for i, trend in enumerate(trends)
        ])

        prompt = f"""Analyze these trending topics from Hacker News and Dev.to:

{trends_text}

Your task: Identify ONE high-value feature or product idea that is relevant to an autonomous software factory that builds products. Focus on:
- AI/ML capabilities that could be automated
- SaaS features that are trending
- Product development tools or workflows
- DevOps/CI/CD innovations

Ignore noise, hype, and ideas that are too vague or complex to implement as a single feature.

If you find a good idea, respond with a JSON object in this format:
{{
    "found": true,
    "idea_name": "Brief name of the idea (max 50 chars)",
    "description": "Clear description of the feature/idea and why it's valuable (2-3 sentences)",
    "source_trends": ["List of 1-3 trend titles that inspired this idea"]
}}

If no good ideas are found, respond with:
{{
    "found": false,
    "reason": "Brief explanation of why these trends aren't suitable"
}}

Respond ONLY with the JSON object, no other text."""

        response = client.messages.create(
            model="claude-sonnet-4-5-20250929",
            max_tokens=1000,
            messages=[{
                "role": "user",
                "content": prompt
            }]
        )

        # Parse Claude's response
        response_text = response.content[0].text.strip()

        # Extract JSON from response (in case Claude adds explanation)
        if "```json" in response_text:
            response_text = response_text.split("```json")[1].split("```")[0].strip()
        elif "```" in response_text:
            response_text = response_text.split("```")[1].split("```")[0].strip()

        result = json.loads(response_text)

        if result.get("found"):
            print(f"   ✓ Found idea: {result['idea_name']}")
            return result
        else:
            print(f"   ℹ️  No suitable ideas found: {result.get('reason', 'Unknown reason')}")
            return None

    except Exception as e:
        print(f"   ✗ Error analyzing with Claude: {e}")
        import traceback
        traceback.print_exc()
        return None


def create_github_issue(idea: Dict) -> bool:
    """
    Create a GitHub issue for the identified idea.

    Args:
        idea: Dictionary with idea_name, description, and source_trends

    Returns:
        True if issue was created successfully, False otherwise
    """
    print(f"\n📝 Creating GitHub issue for: {idea['idea_name']}")

    github_token = os.environ.get("GITHUB_TOKEN")
    if not github_token:
        print("   ✗ Error: GITHUB_TOKEN not found in environment")
        return False

    if not GITHUB_REPO:
        print("   ✗ Error: GITHUB_REPOSITORY not found in environment")
        return False

    try:
        # Prepare issue body
        sources_text = "\n".join([f"- {source}" for source in idea['source_trends']])

        body = f"""{idea['description']}

## Source Trends
{sources_text}

## Next Steps
- [ ] Research implementation approach
- [ ] Design architecture
- [ ] Create development plan
- [ ] Implement feature

---
*Generated by Trend Hunter Agent on {datetime.now().strftime('%Y-%m-%d at %H:%M UTC')}*"""

        # Create issue via GitHub API
        url = f"{GITHUB_API_URL}/repos/{GITHUB_REPO}/issues"
        headers = {
            "Authorization": f"token {github_token}",
            "Accept": "application/vnd.github.v3+json"
        }
        payload = {
            "title": f"🚀 Market Trend: {idea['idea_name']}",
            "body": body,
            "labels": ["trend-hunter", "market-research", "enhancement"]
        }

        response = requests.post(url, headers=headers, json=payload, timeout=10)
        response.raise_for_status()

        issue_data = response.json()
        issue_url = issue_data.get('html_url', '')

        print(f"   ✓ Issue created: {issue_url}")
        return True

    except Exception as e:
        print(f"   ✗ Error creating GitHub issue: {e}")
        import traceback
        traceback.print_exc()
        return False


def main():
    """Main execution function."""
    print("🎯 Trend Hunter Agent - Starting External Research")
    print("=" * 70)

    try:
        # Fetch trends from multiple sources
        hn_stories = fetch_hacker_news_stories(count=10)
        devto_articles = fetch_devto_articles(count=10)

        # Combine all trends
        all_trends = hn_stories + devto_articles

        if not all_trends:
            print("\n⚠️  No trends fetched. Exiting.")
            return 1

        print(f"\n📊 Total trends collected: {len(all_trends)}")

        # Analyze trends with Claude
        idea = analyze_trends_with_claude(all_trends)

        if idea and idea.get('found'):
            # Create GitHub issue
            success = create_github_issue(idea)

            if success:
                print("\n✅ Trend Hunter completed successfully!")
                return 0
            else:
                print("\n⚠️  Failed to create GitHub issue")
                return 1
        else:
            print("\n✅ Trend Hunter completed - No actionable ideas found")
            return 0

    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    try:
        exit(main())
    except KeyboardInterrupt:
        print("\n\n⚠️  Trend Hunter interrupted by user")
        exit(130)
