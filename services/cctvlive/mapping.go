package cctvlive

import (
	"encoding/json"
	"regexp"
	"strings"
)

// OfficialIDs are upstream identifiers. BookStark's channel key remains stable.
type OfficialIDs struct {
	PID      string `json:"pid"`
	StreamID string `json:"streamId"`
}

var decimalID = regexp.MustCompile(`^[1-9][0-9]{0,18}$`)

func (ids OfficialIDs) Valid() bool {
	return decimalID.MatchString(ids.PID) && decimalID.MatchString(ids.StreamID)
}

type OfficialChannel struct {
	ID      string
	Key     string
	Name    string
	Default OfficialIDs
}

func DefaultIDs(key string) OfficialIDs {
	pair := channels[key]
	return OfficialIDs{PID: pair[1], StreamID: pair[0]}
}

// Offer channels that actually have an in-player Yangshipin source.
func OfficialChannels() []OfficialChannel {
	var catalog struct {
		Channels []struct {
			Name    string
			ID      string
			Sources []struct{ Original string }
		}
	}
	if err := json.Unmarshal(defaultCatalog, &catalog); err != nil {
		panic(err)
	}
	var list []OfficialChannel
	for _, ch := range catalog.Channels {
		for _, s := range ch.Sources {
			key, ok := strings.CutPrefix(s.Original, "cctvlive://")
			if ok && DefaultIDs(key).Valid() {
				list = append(list, OfficialChannel{ch.ID, key, ch.Name, DefaultIDs(key)})
				break
			}
		}
	}
	return list
}
