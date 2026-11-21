#include "test_util.h"
#include "noshi_translate_llm.h"

#include <string.h>

#define AI_STUDIO "https://generativelanguage.googleapis.com/v1beta/openai"
#define VERTEX "https://aiplatform.googleapis.com/v1"
#define OPENROUTER "https://openrouter.ai/api/v1"
#define GATEWAY "https://ai-gateway.vercel.sh/v1"

static void test_temperature(void) {
    CHECK(noshi_llm_supports_temperature("gpt-4o"));
    CHECK(!noshi_llm_supports_temperature("gpt-5"));
    CHECK(!noshi_llm_supports_temperature("openai/GPT-5.6-luna"));
    CHECK(noshi_llm_supports_temperature("gemini-2.5-flash"));
    CHECK(noshi_llm_supports_temperature("gemini-3.1-flash-lite"));
    CHECK(!noshi_llm_supports_temperature("gemini-3.5-flash"));
    CHECK(!noshi_llm_supports_temperature("gemini-flash-latest"));
    CHECK(noshi_llm_supports_temperature("deepseek-v4-flash"));
    /* no name, nothing to refuse */
    CHECK(noshi_llm_supports_temperature(""));
    CHECK(noshi_llm_supports_temperature(NULL));
}

static void plan(const char *url, const char *model, noshi_llm_reasoning_style style, const char *effort) {
    noshi_llm_reasoning p;
    noshi_llm_plan_reasoning(url, model, &p);
    CHECK_EQ_INT(p.style, style);
    if (effort) CHECK(!strcmp(p.effort, effort));
}

static void test_reasoning(void) {
    plan("https://api.openai.com/v1", "gpt-5.6-luna", NOSHI_LLM_REASONING_EFFORT, "none");
    plan("https://api.openai.com/v1", "gpt-5-mini", NOSHI_LLM_REASONING_EFFORT, "minimal");
    plan("https://api.openai.com/v1", "gpt-5-chat-latest", NOSHI_LLM_REASONING_NONE, NULL);
    plan("https://api.openai.com/v1", "gpt-5.1-instant", NOSHI_LLM_REASONING_NONE, NULL);
    plan("https://api.groq.com/openai/v1", "openai/gpt-oss-120b", NOSHI_LLM_REASONING_EFFORT, "low");
    plan("https://api.x.ai/v1", "grok-4-fast-non-reasoning", NOSHI_LLM_REASONING_NONE, NULL);
    plan("https://api.x.ai/v1", "grok-4", NOSHI_LLM_REASONING_EFFORT, "low");
    plan("https://api.deepseek.com/v1", "deepseek-v4-flash", NOSHI_LLM_REASONING_THINKING_OFF, NULL);
    plan("https://api.deepseek.com/v1", "deepseek-chat", NOSHI_LLM_REASONING_EFFORT, "none");
    plan(AI_STUDIO, "gemini-flash-lite-latest", NOSHI_LLM_REASONING_EFFORT, "minimal");
    plan(AI_STUDIO, "gemini-flash-latest", NOSHI_LLM_REASONING_EFFORT, "low");
    plan(AI_STUDIO, "gemini-3.5-flash-lite", NOSHI_LLM_REASONING_EFFORT, "minimal");
    plan(AI_STUDIO, "gemini-2.5-flash", NOSHI_LLM_REASONING_EFFORT, "none");
    plan(AI_STUDIO, "gemini-2.5-pro", NOSHI_LLM_REASONING_EFFORT, "low");
    plan("https://ollama.com/v1", "gemma4:31b", NOSHI_LLM_REASONING_EFFORT, "minimal");
    plan("https://x.test/v1", "", NOSHI_LLM_REASONING_EFFORT, "none");
    plan("https://x.test/v1", NULL, NOSHI_LLM_REASONING_EFFORT, "none");
    /* the routers take their own form, but only for a model named with a provider */
    plan(OPENROUTER, "openrouter/free", NOSHI_LLM_REASONING_ROUTER, "none");
    plan(OPENROUTER, "gemini-3.5-flash-lite", NOSHI_LLM_REASONING_EFFORT, "minimal");
    plan(GATEWAY, "google/gemma-4-31b-it", NOSHI_LLM_REASONING_GATEWAY, "minimal");
    plan(GATEWAY, "deepseek/deepseek-v4-flash", NOSHI_LLM_REASONING_GATEWAY_DEEPSEEK_OFF, NULL);
    plan(GATEWAY, "DeepSeek/deepseek-v3", NOSHI_LLM_REASONING_GATEWAY, "none");
    plan(GATEWAY, "openai/gpt-5-chat", NOSHI_LLM_REASONING_NONE, NULL);
}

static void test_vertex(void) {
    noshi_llm_reasoning p;
    noshi_llm_plan_reasoning(VERTEX, "gemini-2.5-flash", &p);
    CHECK_EQ_INT(p.style, NOSHI_LLM_REASONING_VERTEX);
    CHECK_EQ_INT(p.has_budget, 1);
    CHECK_EQ_INT(p.budget, 0);
    noshi_llm_plan_reasoning(VERTEX, "gemini-2.5-pro", &p);
    CHECK_EQ_INT(p.budget, 128);
    noshi_llm_plan_reasoning(VERTEX, "gemini-3.5-flash-lite", &p);
    CHECK_EQ_INT(p.has_budget, 0);
    CHECK(!strcmp(p.level, "MINIMAL"));
    noshi_llm_plan_reasoning(VERTEX, "gemini-3.7-flash", &p);
    CHECK(!strcmp(p.level, "LOW"));
    noshi_llm_plan_reasoning(VERTEX, "gemini-3-pro", &p);
    CHECK(!strcmp(p.level, "LOW"));
    noshi_llm_plan_reasoning(VERTEX, "gemini-flash-latest", &p);
    CHECK(!strcmp(p.level, "LOW"));
    noshi_llm_plan_reasoning(VERTEX, "models/gemini-3.5-flash", &p);
    CHECK(!strcmp(p.level, "MINIMAL"));
}

static void test_user_prompt(void) {
    char out[256];
    CHECK_EQ_INT(noshi_llm_user_prompt("", "Hola", "Russian", 0, out, sizeof(out)), NOSHI_OK);
    CHECK(!strcmp(out, "Translate to Russian: <TEXT>Hola</TEXT>"));
    CHECK_EQ_INT(noshi_llm_user_prompt(NULL, "Hola", "Russian", 1, out, sizeof(out)), NOSHI_OK);
    CHECK(!strcmp(out, "Translate to Russian: <TEXT>Hola</TEXT>"));
    CHECK_EQ_INT(noshi_llm_user_prompt("Into @toLang: @text. Again @toLang", "Hola", "Russian", 0, out, sizeof(out)), NOSHI_OK);
    CHECK(!strcmp(out, "Into Russian: <TEXT>Hola</TEXT>. Again Russian"));
    CHECK_EQ_INT(noshi_llm_user_prompt("@text -> @toLang", "Hola", "Russian", 1, out, sizeof(out)), NOSHI_OK);
    CHECK(!strcmp(out, "Hola -> Russian"));
    /* a text that holds a mark is not read as a mark */
    CHECK_EQ_INT(noshi_llm_user_prompt("@text to @toLang", "say @toLang @text", "Russian", 1, out, sizeof(out)), NOSHI_OK);
    CHECK(!strcmp(out, "say @toLang @text to Russian"));
    CHECK_EQ_INT(noshi_llm_user_prompt("no marks", "x", "Russian", 0, out, sizeof(out)), NOSHI_OK);
    CHECK(!strcmp(out, "no marks"));
    CHECK_EQ_INT(noshi_llm_user_prompt("@text", "this does not fit", "Russian", 1, out, 8), NOSHI_E_LIMIT);
    CHECK_EQ_INT(out[0], 0);
    CHECK_EQ_INT(noshi_llm_user_prompt("@text", "x", "Russian", 1, NULL, 8), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_llm_user_prompt("@text", NULL, "Russian", 1, out, 8), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_llm_user_prompt("@text", "x", "Russian", 1, out, 0), NOSHI_E_ARG);
}

static void test_context_and_system(void) {
    char out[256];
    CHECK_EQ_INT(noshi_llm_context_prompt("a\nb", out, sizeof(out)), NOSHI_OK);
    CHECK(!strcmp(out, "Context for reference only (do not translate or repeat it):\n<CONTEXT>\na\nb\n</CONTEXT>"));
    CHECK_EQ_INT(noshi_llm_context_prompt("a\nb", out, 20), NOSHI_E_LIMIT);
    CHECK_EQ_INT(noshi_llm_context_prompt(NULL, out, sizeof(out)), NOSHI_E_ARG);
    CHECK(strstr(noshi_llm_default_system(), "<TEXT>...</TEXT>") != NULL);
    CHECK(strlen(noshi_llm_default_system()) > 500);
}

int main(void) {
    test_temperature();
    test_reasoning();
    test_vertex();
    test_user_prompt();
    test_context_and_system();
    return test_finish("test_translate_llm");
}
