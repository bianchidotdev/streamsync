package main

import (
	"context"
	"encoding/json"
	"fmt"
	termtables "github.com/brettski/go-termtables"
	_ "github.com/joho/godotenv/autoload"
	"github.com/zmb3/spotify/v2"
	spotifyauth "github.com/zmb3/spotify/v2/auth"
	"golang.org/x/oauth2/clientcredentials"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

func spotifyAuth(ctx context.Context) *spotify.Client {
	config := &clientcredentials.Config{
		ClientID:     os.Getenv("SPOTIFY_ID"),
		ClientSecret: os.Getenv("SPOTIFY_SECRET"),
		TokenURL:     spotifyauth.TokenURL,
	}
	token, err := config.Token(ctx)
	if err != nil {
		log.Fatalf("couldn't get token: %v", err)
	}

	httpClient := spotifyauth.New().Client(ctx, token)
	client := spotify.New(httpClient)
	return client
}

type Artist struct {
	Name string
}

// type Artists []*Artist

// func (artists Artists) String() string {
// 	names := []string{}
// 	for _, a := range artists {
// 		names = append(names, a.Name)
// 	}
//     return strings.Join(names, ", ")
// }

type Track struct {
	Name     string
	Artists  []*Artist
	Album    string
	Duration time.Duration
}

type Playlist struct {
	Name        string
	Description string
	Tracks      []*Track
}

func (p Playlist) FormatCLI() string {
	table := termtables.CreateTable()

	table.AddHeaders("Name", "Artists", "Album", "Duration")
	for _, t := range p.Tracks {
		names := []string{}
		for _, a := range t.Artists {
			names = append(names, a.Name)
		}
		artists := strings.Join(names, ", ")
		table.AddRow(t.Name, artists, t.Album, t.Duration)
	}
	return fmt.Sprintf(
		"%s\n%s\n\n%d Songs\n%s",
		p.Name,
		p.Description,
		len(p.Tracks),
		table.Render(),
	)
}

func getPlaylist(playlist_id string) Playlist {
	ctx := context.Background()
	client := spotifyAuth(ctx)
	spotifyPlaylist, err := client.GetPlaylist(ctx, spotify.ID(playlist_id))
	if err != nil {
		log.Fatalf("couldn't get features playlists: %v", err)
	}
	playlist := Playlist{
		Name:        spotifyPlaylist.SimplePlaylist.Name,
		Description: spotifyPlaylist.SimplePlaylist.Description,
	}

	tracks := []*Track{}
	for _, track := range spotifyPlaylist.Tracks.Tracks {
		artists := []*Artist{}
		for _, a := range track.Track.SimpleTrack.Artists {
			artists = append(artists, &Artist{Name: a.Name})
		}
		duration := time.Duration(int64(track.Track.SimpleTrack.Duration) * int64(time.Millisecond))
		t := &Track{
			Name:     track.Track.SimpleTrack.Name,
			Artists:  artists,
			Album:    track.Track.Album.Name,
			Duration: duration,
		}
		tracks = append(tracks, t)
	}
	playlist.Tracks = tracks

	return playlist
}

var (
	tidalAPIKey = os.Getenv("TIDAL_BEARER_TOKEN")
	tidalHost   = "listen.tidal.com"
)

func main() {
	spotifyPlaylist := getPlaylist("37i9dQZF1DX8Uebhn9wzrS")

	fmt.Println(spotifyPlaylist.FormatCLI())

	client := &http.Client{}
	tidalFolder, err := findOrMakeTidalFolder(client)
	if err != nil {
		log.Fatal(err)
	}

	// sketchy hack to deal with uri encoding not working as expected
	playlistName := strings.Replace(spotifyPlaylist.Name, " ", "_", -1)
	// playlistName := spotifyPlaylist.Name
	tidalPlaylist, err := findOrMakeTidalPlaylist(client, tidalFolder, playlistName)
	if err != nil {
		log.Fatal(err)
	}

	for _, track := range spotifyPlaylist.Tracks {
		tidalTrack, err := findOrMakeTidalTrack(client, tidalPlaylist, track)
		if err != nil {
			log.Fatal(err)
		}
		fmt.Println(tidalTrack)
	}
}

func findOrMakeTidalTrack(client *http.Client, tidalPlaylist *TidalItem, track *Track) (*TidalTrack, error) {
	trackResp, err := getTidalTracks(client, tidalPlaylist)
	if err != nil {
		return nil, err
	}
	fmt.Println(trackResp)
	return nil, nil
}

func getTidalTracks(client *http.Client, tidalPlaylist *TidalItem) ([]*TidalTrack, error) {
	path := fmt.Sprintf("/v1/playlists/%s/items", tidalPlaylist.Data.Uuid)
	query := "offset=0&limit=50&countryCode=US&locale=en_US&deviceType=BROWSER"
	url := buildTidalURL(path, query)

	resp, err := makeTidalRequest(client, "GET", url)
	if err != nil {
		return nil, err
	}

	// TODO: pagination

	body, err := readResp(resp)
	if err != nil {
		return nil, err
	}

	trackResp := &TidalPlaylistItemsResponse{}
	err = json.Unmarshal(body, trackResp)
	if err != nil {
		return nil, err
	}

	return trackResp.Items, nil
}

func findOrMakeTidalPlaylist(client *http.Client, folder *TidalItem, name string) (*TidalItem, error) {
	folderResp, err := getTidalFolders(client, folder)
	if err != nil {
		return nil, err
	}

	playlist := findItem(folderResp, name)

	if playlist == nil {
		fmt.Printf("Could not find playlist %s, creating a new playlist\n", name)
		playlist, err = makeTidalPlaylist(client, folder, name)
		if err != nil {
			log.Fatal("Failed to create playlist ", err)
		}
		if playlist == nil {
			log.Fatal("Failed to find a playlist")
		}
	}

	fmt.Printf("Using playlist %s (%s)\n", playlist.Name, playlist.Data.Uuid)
	return playlist, nil
}

func makeTidalPlaylist(client *http.Client, folder *TidalItem, name string) (*TidalItem, error) {
	path := "/v2/my-collection/playlists/folders/create-playlist"
	query := fmt.Sprintf("description=&folderId=%s&isPublic=false&name=%s&countryCode=US&locale=en_US&deviceType=BROWSER", folder.Data.Id, name)
	// query := map[string]string{
	// 	"description": "",
	// 	"folderId": folder.Data.Id,
	// 	"isPublic": "false",
	// 	"name": name,
	// 	"countryCode": "US",
	// 	"locale": "en_US",
	// 	"deviceType": "BROWSER",
	// }
	url := buildTidalURL(path, query)
	resp, err := makeTidalRequest(client, "PUT", url)
	if err != nil {
		return nil, err
	}
	body, err := readResp(resp)
	if err != nil {
		return nil, err
	}
	playlist := &TidalItem{}
	err = json.Unmarshal(body, playlist)
	if err != nil {
		return nil, err
	}

	return playlist, nil

}

func findOrMakeTidalFolder(client *http.Client) (*TidalItem, error) {
	folderResp, err := getTidalFolders(client, nil)
	if err != nil {
		log.Fatal("Could not get tidal folders", err)
	}

	folderName := os.Getenv("TIDAL_TRANSFER_FOLDER")
	if folderName == "" {
		folderName = "spotify"
	}

	folder := &TidalItem{}
	if folderName == "root" {
		folder = &TidalItem{
			Name: "root",
			Data: &TidalItemData{
				Id: "root",
			},
		}
	} else {
		folder = findItem(folderResp, folderName)
		if folder == nil {
			fmt.Printf("Could not find folder %s, creating a new folder\n", folderName)
			folder, err = makeTidalFolder(client, folderName)
			if err != nil {
				log.Fatal("Failed to create folder", err)
			}
			if folder == nil {
				log.Fatal("Failed to find a folder")
			}
		}

		fmt.Printf("Using folder %s (%s)\n", folder.Name, folder.Data.Id)
	}
	return folder, nil
}

func makeTidalFolder(client *http.Client, folderName string) (*TidalItem, error) {
	path := "/v2/my-collection/playlists/folders/create-folder"
	query := fmt.Sprintf("folderId=root&name=%s&trns=&countryCode=US&locale=en_US&deviceType=BROWSER", folderName)
	url := buildTidalURL(path, query)
	resp, err := makeTidalRequest(client, "PUT", url)
	if err != nil {
		return nil, err
	}
	body, err := readResp(resp)
	folder := &TidalItem{}
	err = json.Unmarshal(body, folder)
	if err != nil {
		return nil, err
	}

	return folder, nil
}

func findItem(folderResp *TidalFolderResponse, itemName string) *TidalItem {
	for _, item := range folderResp.Items {
		if item.Name == itemName {
			return item
		}
	}

	return nil
}

type TidalPlaylistItemsResponse struct {
	Items []*TidalTrack
}

type TidalTrack struct {
	Id       string
	Title    string
	Duration int // seconds
	Artists  []*TidalArtist
	Album    *TidalAlbum
}

type TidalArtist struct {
	Id   int
	Name string
	Type string
}

type TidalAlbum struct {
	Id    int
	Title string
}

type TidalFolderResponse struct {
	Items []*TidalItem
}

type TidalItem struct {
	ItemType string
	Name     string
	Data     *TidalItemData
}

type TidalItemData struct {
	Id   string
	Uuid string
}

func buildTidalURL(path string, query string) *url.URL {
	// values := &url.Values{}
	// for key, value := range query {
	// 	values.Set(key, value)
	// }
	return &url.URL{
		Scheme:   "https",
		Host:     tidalHost,
		Path:     path,
		RawQuery: query,
	}
}

func makeTidalRequest(client *http.Client, method string, url *url.URL) (*http.Response, error) {
	req, err := http.NewRequest(method, url.String(), nil)
	if err != nil {
		return nil, err
	}
	req.Header.Add("Authorization", fmt.Sprintf("Bearer %s", tidalAPIKey))
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("Tidal returned error code %s", resp.StatusCode)
	}
	return resp, nil
}

func readResp(resp *http.Response) ([]byte, error) {
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	return body, nil
}

func getTidalFolders(client *http.Client, folder *TidalItem) (*TidalFolderResponse, error) {
	if folder == nil {
		folder = &TidalItem{
			Name: "root",
			Data: &TidalItemData{
				Id: "root",
			},
		}
	}

	path := "/v2/my-collection/playlists/folders"
	// query := url.QueryEscape(fmt.Sprintf("folderId=%s&includeOnly=&offset=0&limit=50&order=DATE&orderDirection=DESC&countryCode=US&locale=en_US&deviceType=BROWSER", folder.Data.Id))
	query := fmt.Sprintf("folderId=%s&includeOnly=&offset=0&limit=50&order=DATE&orderDirection=DESC&countryCode=US&locale=en_US&deviceType=BROWSER", folder.Data.Id)
	// query := map[string]string{
	// 	"folderId": folder.Data.Id,
	// 	"includeOnly": "&offset",
	// 	"limit": "50",
	// 	"order": "DATE",
	// 	"orderDirection": "DESC",
	// 	"countryCode": "US",
	// 	"locale": "en_US",
	// 	"deviceType": "BROWSER",
	// }
	url := buildTidalURL(path, query)

	fmt.Println(url.String())
	resp, err := makeTidalRequest(client, "GET", url)
	if err != nil {
		return nil, err
	}
	body, err := readResp(resp)
	if err != nil {
		return nil, err
	}

	folderResp := &TidalFolderResponse{}
	err = json.Unmarshal(body, folderResp)
	if err != nil {
		return nil, err
	}

	return folderResp, nil
	// Need to pull out .items[] | {itemType, name}
}
