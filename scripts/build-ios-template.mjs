// Regenerates ios/body-template.json from ios/system-prompt.txt.
// The template is one line of JSON with two plain-text slots the shortcut fills with Replace Text (regex off).
import { readFileSync, writeFileSync } from 'node:fs';

const system = readFileSync(new URL('../ios/system-prompt.txt', import.meta.url), 'utf8').trim();
const body = {
  model: 'claude-sonnet-5-5',
  max_tokens: 4000,
  thinking: { type: 'adaptive' },
  output_config: {
    effort: 'low',
    format: {
      type: 'json_schema',
      schema: {
        type: 'object',
        properties: { translation: { type: 'string' }, back_translation: { type: 'string' } },
        required: ['translation', 'back_translation'],
        additionalProperties: false,
      },
    },
  },
  system,
  messages: [{
    role: 'user',
    content: [
      { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: '{{IMAGE_B64}}' } },
      { type: 'text', text: '{{TEXT}}' },
    ],
  }],
};
writeFileSync(new URL('../ios/body-template.json', import.meta.url), JSON.stringify(body) + '\n');
