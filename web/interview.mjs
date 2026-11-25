const questTopic = (track) => "quest:" + track;
const theoryTopic = (id) => "theory:" + id;

export function interviewTopics({ quests, theory }) {
  return [
    ...Array.from(new Set(quests.map(({ topic }) => topic)), (track) => ({
      id: questTopic(track), track,
    })),
    ...theory.map(({ id, title }) => ({ id: theoryTopic(id), title })),
  ];
}

export function filterInterview({ quests, theory }, { query, topic, status }, read, language) {
  const normalize = (text) => text.normalize("NFC").toLocaleLowerCase(language);
  const terms = normalize(query.trim()).split(/\s+/u).filter(Boolean);
  const bands = new Map(), theoryMatches = [];
  let count = 0;

  function matchingQuestions(group) {
    if (!terms.length) return group.questions;
    return group.questions.filter(({ prompt, points }) => {
      const text = normalize([prompt, ...points].map(read).join("\n"));
      return terms.every((term) => text.includes(term));
    });
  }

  for (const quest of quests) {
    if (topic && topic !== questTopic(quest.topic)) continue;
    if (status && status !== (quest.completed ? "completed" : "incomplete")) continue;
    const questions = matchingQuestions(quest);
    if (!questions.length) continue;
    if (!bands.has(quest.difficulty)) {
      bands.set(quest.difficulty, { difficulty: quest.difficulty, count: 0, topics: new Map() });
    }
    const band = bands.get(quest.difficulty);
    if (!band.topics.has(quest.topic)) {
      band.topics.set(quest.topic, { track: quest.topic, count: 0, quests: [] });
    }
    const track = band.topics.get(quest.topic);
    track.quests.push({ ...quest, questions });
    track.count += questions.length;
    band.count += questions.length;
    count += questions.length;
  }

  let theoryCount = 0;
  if (!status || status === "theory") {
    for (const group of theory) {
      if (topic && topic !== theoryTopic(group.id)) continue;
      const questions = matchingQuestions(group);
      if (!questions.length) continue;
      theoryMatches.push({ ...group, questions });
      theoryCount += questions.length;
    }
  }

  return {
    bands: Array.from(bands.values(), (band) => ({ ...band, topics: [...band.topics.values()] })),
    theory: theoryMatches,
    theoryCount,
    count: count + theoryCount,
  };
}
