// Every Instagram DOM assumption lives here. When Instagram changes, re-run the Task 3 spike and edit this file.
export const SEL = {
  threadRoot: '[role="main"]',                                     // holds the message scroller (and the inbox list, which has no articles)
  messageRow: '[role="article"][aria-roledescription="message"]',  // one message
  messageText: 'div[dir="auto"]',                                  // leaf text div inside a text bubble; media captions are span-only
  composer: 'div[role="textbox"][contenteditable="true"]',         // Lexical editor
  replyLabelPrefix: 'Reply to message from ',
  viewerAvatar: 'img[alt$="\'s profile picture"]',
};

const AVATAR_SUFFIX = "'s profile picture";

// Viewer username from the sidebar profile link (outside main). null if not found = selector miss.
export function findViewerName(doc) {
  for (const img of doc.querySelectorAll(`a[href] ${SEL.viewerAvatar}`)) {
    if (img.closest(SEL.threadRoot)) continue;
    const alt = img.getAttribute('alt');
    return alt.slice(0, -AVATAR_SUFFIX.length);
  }
  return null;
}

// 'me' | 'partner'. The reply button lives in the row group, a sibling of the article.
// Group chats: everyone except the viewer counts as partner, the safe direction.
export function senderOf(row, viewer) {
  const label = row.closest('[role="group"]')
    ?.querySelector(`[aria-label^="${SEL.replyLabelPrefix}"]`)
    ?.getAttribute('aria-label');
  const name = label ? label.slice(SEL.replyLabelPrefix.length) : null;
  return name === viewer ? 'me' : 'partner';
}
