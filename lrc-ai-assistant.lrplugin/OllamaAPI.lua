OllamaAPI = {}
OllamaAPI.__index = OllamaAPI

function OllamaAPI:new()
    local o = setmetatable({}, OllamaAPI)
    self.url = Defaults.baseUrls.ollama
    
    -- Only set model details if we're using this for requests
    if prefs.ai and string.sub(prefs.ai, 1, 6) == 'ollama' then
        self.model = prefs.ai
        self.ollamaModel = string.sub(prefs.ai, 8, -1)
    end

    return o
end

function OllamaAPI:doRequest(filePath, task, systemInstruction, generationConfig)
    local body = {
        model = self.ollamaModel,
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

    local response, headers = LrHttp.post(self.url, JSON:encode(body), {{ field = 'Content-Type', value = 'application/json' }})

    if headers.status == 200 then
        if response ~= nil then
            log:trace(response)
            local decoded = JSON:decode(response)
            if decoded ~= nil then
                if decoded.choices[1].finish_reason == 'stop' then
                    local text = JSON:decode(decoded.choices[1].message.content)
                    log:trace(Util.dumpTable(text))
                    log:trace(text)
                    return true, text, 0, 0
                else
                    log:error('Blocked: ' .. decoded.choices[1].finish_reason .. Util.dumpTable(decoded.choices[1]))
                    return false,  decoded.choices[1].finish_reason, 0, 0
                end
            end
        else
            log:error('Got empty response from ChatGPT')
        end
    else
        log:error('OllamaAPI POST request failed. ' .. self.url)
        log:error(Util.dumpTable(headers))
        log:error(response)
        return false, nil, 0, 0
    end
end


function OllamaAPI:analyzeImage(filePath, metadata)
    local task = prefs.task
    if metadata ~= nil then
        if prefs.submitGPS and metadata.gps ~= nil then
            task = task .. " " .. LOC "$$$/lrc-ai-assistant/ChatGptAPI/gpsAddon=This photo was taken at the following coordinates:" .. metadata.gps.latitude .. ", " .. metadata.gps.longitude
        end
        if prefs.submitKeywords and metadata.keywords ~= nil then
            task = task .. " " .. LOC "$$$/lrc-ai-assistant/ChatGptAPI/keywordAddon=Some keywords are:" .. metadata.keywords
        end
        if metadata.context ~= nil and metadata.context ~= "" then
            log:trace("Preflight context given")
            task = task .. " " .. metadata.context
        end
    end

    local success, result, inputTokenCount, outputTokenCount = self:doRequest(filePath, task, prefs.systemInstruction, ResponseStructure:new():generateResponseStructure())
    if success then
        return success, result, inputTokenCount, outputTokenCount
    end
    return false, "", inputTokenCount, outputTokenCount
end

-- Standalone function to fetch Ollama models without needing a class instance
function OllamaAPI.fetchAvailableModels()
    local url = "http://localhost:11434/api/tags"
    
    local response, headers = LrHttp.get(url)
    
    if headers.status == 200 and response ~= nil then
        log:trace("Ollama models response: " .. response)
        local decoded = JSON:decode(response)
        if decoded ~= nil and decoded.models ~= nil then
            local ollamaModels = {}
            
            for _, model in ipairs(decoded.models) do
                -- Include all models as we can't reliably check for vision support from the API
                table.insert(ollamaModels, { 
                    title = 'Ollama ' .. model.name, 
                    value = 'ollama-' .. model.name 
                })
            end
            
            return true, ollamaModels
        else
            log:error("Failed to parse Ollama models response")
            return false, "Failed to parse models response"
        end
    else
        log:error("Failed to fetch Ollama models. Status: " .. (headers.status or "unknown"))
        return false, "Failed to connect to Ollama server"
    end
end
