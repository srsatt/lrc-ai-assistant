ChatGptAPI = {}
ChatGptAPI.baseUrl = 'https://api.openai.com/v1/chat/completions'
ChatGptAPI.__index = ChatGptAPI

function ChatGptAPI:new()
    local o = setmetatable({}, ChatGptAPI)
    self.rateLimitHit = 0

    if Util.nilOrEmpty(prefs.chatgptApiKey) then
        Util.handleError('ChatGPT API key not configured.', LOC "$$$/lrc-ai-assistant/ChatGptAPI/NoAPIkey=No ChatGPT API key configured in Add-Ons manager.")
        return nil
    else
        self.apiKey = prefs.chatgptApiKey
    end

    self.url = ChatGptAPI.baseUrl

    return o
end

function ChatGptAPI:doRequest(filePath, task, systemInstruction, generationConfig)
    local body = {
        model = "gpt-4o",
        response_format = generationConfig,
        messages = {
            {
                role = "system",
                content = systemInstruction,
            },
            {
                role = "user",
                content = task,
            },
            {
                role = "user",
                content = {
                    {
                        type = "image_url",
                        image_url = {
                            url = "data:image/jpeg;base64," .. Util.encodePhotoToBase64(filePath)
                        }
                    }
                }
            }
        }
    }

    log:trace(Util.dumpTable(body))


    -- This is dirty!
    local jsonBody = JSON:encode(body)
    jsonBody = string.gsub(jsonBody, "STRING", "string")
    jsonBody = string.gsub(jsonBody, "ARRAY", "array")
    jsonBody = string.gsub(jsonBody, "OBJECT", "object")


    local response, headers = LrHttp.post(self.url, jsonBody, {{ field = 'Content-Type', value = 'application/json' },  { field = 'Authorization', value = 'Bearer ' .. self.apiKey }})

    if headers.status == 200 then
        self.rateLimitHit = 0
        if response ~= nil then
            log:trace(response)
            local decoded = JSON:decode(response)
            if decoded ~= nil then
                if decoded.choices[1].finish_reason == 'stop' then
                    local text = decoded.choices[1].message.content
                    log:trace(text)
                    return true, text, 0, 0 -- FIXME
                else
                    log:error('Blocked: ' .. decoded.choices[1].finish_reason .. Util.dumpTable(decoded.choices[1]))
                    return false,  decoded.choices[1].finish_reason, 0, 0
                end
            end
        else
            log:error('Got empty response from ChatGPT')
        end
    else
        log:error('ChatGptAPI POST request failed. ' .. self.url)
        log:error(Util.dumpTable(headers))
        log:error(response)
        return false, nil, 0, 0 -- FIXME
    end
end


function ChatGptAPI:analyzeImage(filePath, metadata)
    local task = Defaults.defaultTask
    if metadata ~= nil then
        if metadata.gps ~= nil then
            task = task .. " " .. LOC "$$$/lrc-ai-assistant/ChatGptAPI/gpsAddon=This photo was taken at the following coordinates:" .. metadata.gps.latitude .. ", " .. metadata.gps.longitude
        end
        if metadata.keywords ~= nil then
            task = task .. " " .. LOC "$$$/lrc-ai-assistant/ChatGptAPI/keywordAddon=Some keywords are:" .. metadata.keywords
        end
    end

    local success, result, inputTokenCount, outputTokenCount = self:doRequest(filePath, task, Defaults.defaultSystemInstruction, Defaults.getDefaultChatGPTGenerationConfig())
    if success then
        return success, JSON:decode(result), inputTokenCount, outputTokenCount
    end
    return false, "", inputTokenCount, outputTokenCount
end
