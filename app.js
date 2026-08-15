const data = window.GRAMMAR_DATA || [];
const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];
const state = { filter: 'all', query: '', quiz: null, questionIndex: 0, answers: [] };
const storage = { settings: 'jlpt-ai-settings', records: 'jlpt-practice-records' };

function getSettings() { return JSON.parse(localStorage.getItem(storage.settings) || '{}'); }
function getRecords() { return JSON.parse(localStorage.getItem(storage.records) || '[]'); }
function setRecords(records) { localStorage.setItem(storage.records, JSON.stringify(records)); }
function escapeHTML(value) { return String(value).replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[char])); }
function showToast(text) { const t = $('#toast'); t.textContent = text; t.classList.add('show'); setTimeout(() => t.classList.remove('show'), 2400); }
function updateAiStatus() { const configured = getSettings().apiKey && getSettings().baseUrl && getSettings().model; $('#ai-status').textContent = configured ? 'AI 已配置' : 'AI 未连接'; $('.status-dot').classList.toggle('connected', Boolean(configured)); }
function levelCounts() { return Object.fromEntries(['N5','N4','N3','N2','N1'].map(level => [level, data.filter(item => item.level === level).length])); }
function formatText(value) { return escapeHTML(value || '').replace(/\n/g, '<br>'); }
function relatedLink(related) { return related ? `<a class="source-link" href="${escapeHTML(related.url)}" target="_blank" rel="noreferrer">${escapeHTML(related.label || '查看 Enuncia 文章')} <span>↗</span></a>` : ''; }

function renderList() {
  const q = state.query.trim().toLowerCase();
  const items = data.filter(item => (state.filter === 'all' || item.level === state.filter) && (!q || `${item.grammar} ${item.meaning} ${item.rule}`.toLowerCase().includes(q)));
  $('#result-count').textContent = `${items.length} 条语法`;
  $('#grammar-list').innerHTML = items.length ? items.map(item => `<details class="grammar-entry"><summary class="grammar-row"><span class="level-pill">${item.level}</span><strong class="grammar-term">${escapeHTML(item.grammar)}</strong><span class="grammar-meaning">${escapeHTML(item.meaning)}</span><span class="grammar-arrow">›</span></summary><div class="grammar-detail"><div><p class="detail-label">接续</p><p>${formatText(item.rule || '原始列表未提供接续规则。')}</p></div>${item.example ? `<div><p class="detail-label">例句</p><p class="example-text">${formatText(item.example)}</p></div>` : ''}${relatedLink(item.related)}</div></details>`).join('') : '<p class="empty-state">没有找到相符的语法。</p>';
}
function renderRecords() {
  const records = getRecords();
  $('#records-list').innerHTML = records.length ? records.map(record => {
    const correct = record.items.filter(item => item.verdict === 'correct').length;
    return `<details class="record"><summary><span class="record-date">${record.date}</span><span class="record-title">${record.title}</span><span class="record-score">${correct}/${record.items.length} 合理</span></summary><div class="record-items">${record.items.map(item => `<article class="record-item"><div><span class="tag ${item.verdict === 'correct' ? 'correct' : ''}">${item.verdict === 'correct' ? '合理' : item.verdict === 'pending' ? '待评判' : '需复习'}</span><p class="record-prompt">${escapeHTML(item.prompt)}</p></div><div><p><b>你的答案：</b>${escapeHTML(item.answer || '未作答')}</p><p><b>参考：</b>${escapeHTML(item.expected)}</p><p class="feedback"><b>AI 评价：</b>${escapeHTML(item.feedback || '尚未取得 AI 评价')}</p></div></article>`).join('')}</div></details>`;
  }).join('') : '<p class="empty-state">还没有练习记录。完成一轮答题后会显示在这里。</p>';
}
function switchView(view) { $$('.view').forEach(el => el.classList.toggle('active', el.id === `${view}-view`)); $$('.nav-item').forEach(el => el.classList.toggle('active', el.dataset.view === view)); $('#section-eyebrow').textContent = view === 'list' ? 'JLPT Grammar Library' : view === 'records' ? 'Practice History' : 'AI Evaluation Setup'; if (view === 'records') renderRecords(); }
function shuffle(list) { return [...list].sort(() => Math.random() - .5); }
function openModal() { $('#quiz-modal').classList.add('open'); $('#quiz-modal').setAttribute('aria-hidden', 'false'); }
function closeModal() { $('#quiz-modal').classList.remove('open'); $('#quiz-modal').setAttribute('aria-hidden', 'true'); }
function makeQuiz(form) {
  const values = new FormData(form); const levels = values.getAll('levels'); const pool = data.filter(item => levels.includes(item.level));
  if (!levels.length) return showToast('请至少选择一个 JLPT 等级。');
  const count = Math.min(Number(values.get('count')), pool.length); const requestedMode = values.get('mode');
  state.quiz = shuffle(pool).slice(0, count).map(item => ({ ...item, direction: requestedMode === 'mixed' ? (Math.random() > .5 ? 'jp-cn' : 'cn-jp') : requestedMode })); state.questionIndex = 0; state.answers = Array(count).fill(''); closeModal(); $('#quiz-screen').hidden = false; renderQuestion();
}
function renderQuestion() { const question = state.quiz[state.questionIndex]; const jpToCn = question.direction === 'jp-cn'; $('#quiz-count').textContent = `${state.questionIndex + 1} / ${state.quiz.length}`; $('#progress-fill').style.width = `${((state.questionIndex + 1) / state.quiz.length) * 100}%`; $('#question-level').textContent = `JLPT ${question.level}`; $('#question-label').textContent = jpToCn ? '写出这个语法的中文含义' : '写出对应的日语语法'; const prompt = $('#question-prompt'); prompt.textContent = jpToCn ? question.grammar : question.meaning; prompt.classList.toggle('chinese-prompt', !jpToCn); $('#question-rule').textContent = jpToCn ? question.rule : '根据中文含义写出对应的日语语法。'; const example = $('#quiz-example'); example.open = false; example.innerHTML = question.example ? `<summary>查看例句</summary><div class="quiz-example-content">${formatText(question.example)}${relatedLink(question.related)}</div>` : ''; example.hidden = !question.example; $('#answer-input').placeholder = jpToCn ? '例如：表示……' : '例如：〜てしまう'; $('#answer-input').value = state.answers[state.questionIndex] || ''; $('#previous-question').style.visibility = state.questionIndex ? 'visible' : 'hidden'; $('#next-question').innerHTML = state.questionIndex === state.quiz.length - 1 ? '提交并评判 <span>→</span>' : '下一题 <span>→</span>'; }
function saveCurrentAnswer() { state.answers[state.questionIndex] = $('#answer-input').value.trim(); }
function moveQuestion(offset) { saveCurrentAnswer(); state.questionIndex += offset; renderQuestion(); }
async function evaluateAnswer(question, answer) {
  const settings = getSettings();
  const jpToCn = question.direction === 'jp-cn'; const prompt = jpToCn ? question.grammar : question.meaning; const expected = jpToCn ? question.meaning : question.grammar;
  if (!(settings.apiKey && settings.baseUrl && settings.model)) return { verdict: 'pending', feedback: '未配置 AI 接口，等待以后评判。' };
  const instruction = `你是一位严谨但鼓励学习者的 JLPT 日语语法教师。请判断用户的开放式答案是否合理，不能只做字符串匹配。题目方向：${jpToCn ? '日语语法到中文含义' : '中文含义到日语语法'}。题目：${prompt}。参考答案：${expected}。学生答案：${answer || '（未作答）'}。${settings.instruction || ''}\n只返回 JSON，格式为 {"verdict":"correct" 或 "incorrect", "feedback":"不超过50字的中文说明"}。`;
  const url = settings.baseUrl.replace(/\/$/, '') + '/chat/completions';
  try { const response = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${settings.apiKey}` }, body: JSON.stringify({ model: settings.model, messages: [{ role: 'user', content: instruction }], temperature: 0.15, response_format: { type: 'json_object' } }) }); if (!response.ok) throw new Error(`接口返回 ${response.status}`); const result = await response.json(); const content = result.choices?.[0]?.message?.content || '{}'; const parsed = JSON.parse(content.match(/\{[\s\S]*\}/)?.[0] || '{}'); return { verdict: parsed.verdict === 'correct' ? 'correct' : 'incorrect', feedback: parsed.feedback || 'AI 未返回评价。' }; } catch (error) { return { verdict: 'pending', feedback: `AI 评判未完成：${error.message}` }; }
}
async function finishQuiz() { saveCurrentAnswer(); $('#next-question').disabled = true; $('#next-question').textContent = 'AI 正在评判…'; const recordItems = []; for (let i = 0; i < state.quiz.length; i++) { const question = state.quiz[i]; const answer = state.answers[i]; const result = await evaluateAnswer(question, answer); const jpToCn = question.direction === 'jp-cn'; recordItems.push({ prompt: jpToCn ? question.grammar : question.meaning, expected: jpToCn ? question.meaning : question.grammar, answer, ...result }); } const date = new Intl.DateTimeFormat('zh-CN', { year:'numeric', month:'2-digit', day:'2-digit', hour:'2-digit', minute:'2-digit', hour12:false }).format(new Date()); const levels = [...new Set(state.quiz.map(item => item.level))].join(' / '); const records = getRecords(); records.unshift({ date, title: `${state.quiz.length} 题 · ${levels}`, items: recordItems }); setRecords(records.slice(0, 100)); $('#quiz-screen').hidden = true; switchView('records'); showToast('本次练习已保存。'); }

function initSettings() { const settings = getSettings(); const form = $('#settings-form'); ['baseUrl','model','apiKey','instruction'].forEach(name => form.elements[name].value = settings[name] || ''); form.addEventListener('submit', (event) => { event.preventDefault(); const values = Object.fromEntries(new FormData(form)); localStorage.setItem(storage.settings, JSON.stringify(values)); $('#save-message').textContent = '已保存'; updateAiStatus(); setTimeout(() => $('#save-message').textContent = '', 1800); }); }
function init() { $('#total-count').textContent = data.length; renderList(); updateAiStatus(); initSettings(); $$('.nav-item').forEach(button => button.addEventListener('click', () => switchView(button.dataset.view))); $('#search-input').addEventListener('input', (event) => { state.query = event.target.value; renderList(); }); $('#level-filters').addEventListener('click', (event) => { const button = event.target.closest('button'); if (!button) return; state.filter = button.dataset.level; $$('#level-filters button').forEach(el => el.classList.toggle('selected', el === button)); renderList(); }); $('#open-setup').addEventListener('click', openModal); $$('.modal [data-close-modal]').forEach(el => el.addEventListener('click', closeModal)); $('#quiz-setup-form').addEventListener('submit', (event) => { event.preventDefault(); makeQuiz(event.currentTarget); }); $('#previous-question').addEventListener('click', () => moveQuestion(-1)); $('#next-question').addEventListener('click', () => state.questionIndex === state.quiz.length - 1 ? finishQuiz() : moveQuestion(1)); $('#answer-input').addEventListener('input', saveCurrentAnswer); $('#quit-quiz').addEventListener('click', () => { if (confirm('结束本次练习？未提交的答案不会保存。')) $('#quiz-screen').hidden = true; }); $('#clear-records').addEventListener('click', () => { if (confirm('确定清除所有练习记录？')) { setRecords([]); renderRecords(); } }); }
init();
