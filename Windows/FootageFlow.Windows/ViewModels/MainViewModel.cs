using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows;
using System.Windows.Data;
using System.Windows.Input;
using FootageFlow.Windows.Infrastructure;
using FootageFlow.Windows.Models;
using FootageFlow.Windows.Services;

namespace FootageFlow.Windows.ViewModels;

public sealed class MainViewModel : ObservableObject
{
    private readonly SettingsService _settings = new();
    private readonly WindowsSecureStore _credentials = new();
    private readonly CoreHostClient _core = new();
    private readonly YtDlpPlatformService _ytDlp = new();
    private readonly LocalizationService _localization;
    private CancellationTokenSource? _searchCancellation;
    private string _currentPage = "search";
    private string _query = "";
    private string _searchStatus = "";
    private bool _isSearching;
    private string _mediaType = "video";
    private string _orientation = "all";
    private string _resolution = "all";
    private string _duration = "all";
    private string _licenseFilter = "all";
    private string _yearFrom = "";
    private string _yearTo = "";
    private bool _downloadableOnly;
    private int _selectedCount;
    private string _sort = "relevance";
    private ProjectRecord? _currentProject;
    private string _newProjectName = "";
    private string _projectEditName = "";
    private string _scriptText = "";

    public MainViewModel()
    {
        _localization = new LocalizationService(_settings);
        _localization.LanguageChanged += (_, _) => RefreshLanguage();
        Downloads = new DownloadQueueService(_core, _settings, _ytDlp, _localization);
        Downloads.DownloadCompleted += (_, _) => _ = LoadDatabaseAsync();
        ResultsView = CollectionViewSource.GetDefaultView(Results);
        ResultsView.Filter = value => value is MediaAsset asset && MatchesFilters(asset);
        ApplySort();
        FavoritesView = CollectionViewSource.GetDefaultView(Favorites);
        FavoritesView.Filter = value => value is SavedAssetRecord record && MatchesProject(record.ProjectID);
        HistoryView = CollectionViewSource.GetDefaultView(History);
        HistoryView.Filter = value => value is SearchHistoryRecord record && MatchesProject(record.ProjectID);
        DownloadRecordsView = CollectionViewSource.GetDefaultView(DownloadRecords);
        DownloadRecordsView.Filter = value => value is DownloadRecord record && MatchesProject(record.ProjectID);
        Providers = new ObservableCollection<ProviderOption>(new[]
        {
            NewProvider("pexels", "Pexels"), NewProvider("pixabay", "Pixabay"),
            NewProvider("wikimedia", "Wikimedia Commons"),
            NewProvider("internetArchive", "Internet Archive"), NewProvider("youtube", "YouTube"),
            NewProvider("nasa", "NASA"), NewProvider("libraryOfCongress", "Library of Congress"),
            NewProvider("nationalArchives", "National Archives"), NewProvider("europeana", "Europeana")
        });
        foreach (var provider in Providers)
            provider.PropertyChanged += (_, args) =>
            {
                if (args.PropertyName != nameof(ProviderOption.Enabled)) return;
                if (provider.Enabled) _settings.Current.EnabledProviders.Add(provider.Id);
                else _settings.Current.EnabledProviders.Remove(provider.Id);
                _settings.Save();
                ResultsView.Refresh();
            };
        NavigateCommand = new RelayCommand(page => CurrentPage = page?.ToString() ?? "search");
        SearchCommand = new AsyncRelayCommand(_ => SearchAsync(), _ => !IsSearching);
        StopSearchCommand = new RelayCommand(_ => _searchCancellation?.Cancel(), _ => IsSearching);
        OpenSourceCommand = new RelayCommand(asset => ShellService.OpenUrl((asset as MediaAsset)?.SourcePageURL));
        PreviewCommand = new RelayCommand(asset => PreviewRequested?.Invoke(asset as MediaAsset));
        FavoriteCommand = new AsyncRelayCommand(asset => ToggleFavoriteAsync(asset as MediaAsset));
        DownloadCommand = new RelayCommand(asset => EnqueueDownload(asset as MediaAsset));
        SelectAllVisibleCommand = new RelayCommand(_ => SelectAllVisible());
        ClearSelectionCommand = new RelayCommand(_ => ClearSelection());
        DownloadSelectedCommand = new RelayCommand(_ => DownloadSelected());
        AddSelectedToProjectCommand = new AsyncRelayCommand(_ => AddSelectedToProjectAsync(),
            _ => CurrentProject is not null && SelectedCount > 0);
        CreateProjectFromSelectionCommand = new AsyncRelayCommand(_ => CreateProjectFromSelectionAsync());
        CopySelectedSourceCommand = new AsyncRelayCommand(_ => CopySelectedSourcesAsync());
        CopySourceCommand = new AsyncRelayCommand(asset => CopyTextAsync(asset as MediaAsset, "formatSource"));
        CopyAttributionCommand = new AsyncRelayCommand(asset => CopyTextAsync(asset as MediaAsset, "formatAttribution"));
        CreateProjectCommand = new AsyncRelayCommand(_ => CreateProjectAsync());
        ClearProjectCommand = new RelayCommand(_ => CurrentProject = null);
        SaveProjectCommand = new AsyncRelayCommand(_ => SaveProjectAsync(), _ => CurrentProject is not null);
        DeleteProjectCommand = new AsyncRelayCommand(project => DeleteProjectAsync(project as ProjectRecord));
        SearchHistoryCommand = new AsyncRelayCommand(history => SearchHistoryAsync(history as SearchHistoryRecord));
        DeleteHistoryCommand = new AsyncRelayCommand(history => DeleteHistoryAsync(history as SearchHistoryRecord));
        ClearHistoryCommand = new AsyncRelayCommand(_ => ClearHistoryAsync());
        CancelDownloadCommand = new RelayCommand(item => Downloads.Cancel((DownloadTaskItem)item!));
        RetryDownloadCommand = new RelayCommand(item => Downloads.Retry((DownloadTaskItem)item!));
        RetryFailedDownloadsCommand = new RelayCommand(_ => Downloads.RetryFailed());
        RevealDownloadCommand = new RelayCommand(item =>
        {
            if ((item as DownloadTaskItem)?.LocalPath is { } path) ShellService.Reveal(path);
        });
        RevealRecordCommand = new RelayCommand(record =>
        {
            if ((record as DownloadRecord)?.LocalPath is { } path) ShellService.Reveal(path);
        });
        OpenRecordCommand = new RelayCommand(record =>
        {
            if ((record as DownloadRecord)?.LocalPath is { } path) ShellService.OpenFile(path);
        });
        OpenRecordSourceCommand = new RelayCommand(record =>
            ShellService.OpenUrl((record as DownloadRecord)?.SourcePageURL));
        RemoveDownloadRecordCommand = new AsyncRelayCommand(record => RemoveDownloadRecordAsync(record as DownloadRecord));
        AnalyzeScriptCommand = new AsyncRelayCommand(_ => AnalyzeScriptAsync());
        RefreshProviderModes();
        SearchStatus = T("search.initialStatus");
        _ = LoadDatabaseAsync();
    }

    public event Action<MediaAsset?>? PreviewRequested;
    public DownloadQueueService Downloads { get; }
    public ObservableCollection<ProviderOption> Providers { get; }
    public ObservableCollection<MediaAsset> Results { get; } = [];
    public ICollectionView ResultsView { get; }
    public ObservableCollection<SearchKeyword> SearchKeywords { get; } = [];
    public ObservableCollection<ProjectRecord> Projects { get; } = [];
    public ObservableCollection<SavedAssetRecord> Favorites { get; } = [];
    public ObservableCollection<SearchHistoryRecord> History { get; } = [];
    public ObservableCollection<DownloadRecord> DownloadRecords { get; } = [];
    public ICollectionView FavoritesView { get; }
    public ICollectionView HistoryView { get; }
    public ICollectionView DownloadRecordsView { get; }
    public ObservableCollection<string> ScriptSegments { get; } = [];

    public ICommand NavigateCommand { get; }
    public ICommand SearchCommand { get; }
    public ICommand StopSearchCommand { get; }
    public ICommand OpenSourceCommand { get; }
    public ICommand PreviewCommand { get; }
    public ICommand FavoriteCommand { get; }
    public ICommand DownloadCommand { get; }
    public ICommand SelectAllVisibleCommand { get; }
    public ICommand ClearSelectionCommand { get; }
    public ICommand DownloadSelectedCommand { get; }
    public ICommand AddSelectedToProjectCommand { get; }
    public ICommand CreateProjectFromSelectionCommand { get; }
    public ICommand CopySelectedSourceCommand { get; }
    public ICommand CopySourceCommand { get; }
    public ICommand CopyAttributionCommand { get; }
    public ICommand CreateProjectCommand { get; }
    public ICommand ClearProjectCommand { get; }
    public ICommand SaveProjectCommand { get; }
    public ICommand DeleteProjectCommand { get; }
    public ICommand SearchHistoryCommand { get; }
    public ICommand DeleteHistoryCommand { get; }
    public ICommand ClearHistoryCommand { get; }
    public ICommand CancelDownloadCommand { get; }
    public ICommand RetryDownloadCommand { get; }
    public ICommand RetryFailedDownloadsCommand { get; }
    public ICommand RevealDownloadCommand { get; }
    public ICommand RevealRecordCommand { get; }
    public ICommand OpenRecordCommand { get; }
    public ICommand OpenRecordSourceCommand { get; }
    public ICommand RemoveDownloadRecordCommand { get; }
    public ICommand AnalyzeScriptCommand { get; }

    public string CurrentPage
    {
        get => _currentPage;
        set
        {
            if (!Set(ref _currentPage, value)) return;
            OnPropertyChanged(nameof(IsSearchPage)); OnPropertyChanged(nameof(IsScriptPage));
            OnPropertyChanged(nameof(IsProjectsPage)); OnPropertyChanged(nameof(IsFavoritesPage));
            OnPropertyChanged(nameof(IsDownloadsPage)); OnPropertyChanged(nameof(IsHistoryPage));
            OnPropertyChanged(nameof(IsSettingsPage));
        }
    }
    public bool IsSearchPage => CurrentPage == "search";
    public bool IsScriptPage => CurrentPage == "script";
    public bool IsProjectsPage => CurrentPage == "projects";
    public bool IsFavoritesPage => CurrentPage == "favorites";
    public bool IsDownloadsPage => CurrentPage == "downloads";
    public bool IsHistoryPage => CurrentPage == "history";
    public bool IsSettingsPage => CurrentPage == "settings";
    public string Query { get => _query; set => Set(ref _query, value); }
    public string SearchStatus { get => _searchStatus; set => Set(ref _searchStatus, value); }
    public bool IsSearching
    {
        get => _isSearching;
        private set
        {
            if (!Set(ref _isSearching, value)) return;
            (SearchCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
            (StopSearchCommand as RelayCommand)?.RaiseCanExecuteChanged();
        }
    }
    public string MediaType { get => _mediaType; set { if (Set(ref _mediaType, value)) ResultsView.Refresh(); } }
    public string Orientation { get => _orientation; set { if (Set(ref _orientation, value)) ResultsView.Refresh(); } }
    public string Resolution { get => _resolution; set { if (Set(ref _resolution, value)) ResultsView.Refresh(); } }
    public string Duration { get => _duration; set { if (Set(ref _duration, value)) ResultsView.Refresh(); } }
    public string LicenseFilter { get => _licenseFilter; set { if (Set(ref _licenseFilter, value)) ResultsView.Refresh(); } }
    public string YearFrom { get => _yearFrom; set { if (Set(ref _yearFrom, Digits(value))) ResultsView.Refresh(); } }
    public string YearTo { get => _yearTo; set { if (Set(ref _yearTo, Digits(value))) ResultsView.Refresh(); } }
    public bool DownloadableOnly { get => _downloadableOnly; set { if (Set(ref _downloadableOnly, value)) ResultsView.Refresh(); } }
    public int SelectedCount
    {
        get => _selectedCount;
        private set
        {
            if (!Set(ref _selectedCount, value)) return;
            OnPropertyChanged(nameof(HasSelection));
            OnPropertyChanged(nameof(SelectionStatus));
            (AddSelectedToProjectCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
        }
    }
    public bool HasSelection => SelectedCount > 0;
    public string Sort
    {
        get => _sort;
        set
        {
            if (!Set(ref _sort, value)) return;
            ApplySort();
        }
    }
    public ProjectRecord? CurrentProject
    {
        get => _currentProject;
        set
        {
            if (!Set(ref _currentProject, value)) return;
            ProjectEditName = value?.Name ?? "";
            ScriptText = value?.Script ?? "";
            (SaveProjectCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
            (AddSelectedToProjectCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
            FavoritesView.Refresh();
            HistoryView.Refresh();
            DownloadRecordsView.Refresh();
        }
    }
    public string NewProjectName { get => _newProjectName; set => Set(ref _newProjectName, value); }
    public string ProjectEditName { get => _projectEditName; set => Set(ref _projectEditName, value); }
    public string ScriptText { get => _scriptText; set => Set(ref _scriptText, value); }
    public string DownloadRoot => _settings.Current.DownloadRoot;
    public string LanguageCode => _localization.Language;
    public string LanguageButton => $"🌐 {_localization.DisplayName}";

    public string T(string key) => _localization.Text(key);
    public string NavSearch => T("nav.quickSearch");
    public string NavScript => T("nav.scriptSearch");
    public string NavProjects => T("nav.projects");
    public string NavFavorites => T("nav.favorites");
    public string NavDownloads => T("nav.downloads");
    public string NavHistory => T("search.history");
    public string NavSettings => T("nav.settings");
    public string SearchTagline => T("search.tagline");
    public string SearchPlaceholder => T("search.placeholder");
    public string SearchApiRecommendation => T("search.apiRecommendation");
    public string SearchButtonText => T("search.button");
    public string StopText => T("common.stop");
    public string KeywordsTitle => T("search.currentKeywords");
    public string TypeTitle => T("filter.type");
    public string OrientationTitle => T("filter.orientation");
    public string ResolutionTitle => T("filter.resolution");
    public string DurationTitle => T("filter.duration");
    public string LicenseTitle => T("filter.license");
    public string SortTitle => T("filter.sort");
    public string ProjectTitle => T("common.project");
    public string ProjectAllText => T("project.all");
    public string ScriptTitle => T("script.title");
    public string ScriptHelp => T("script.help");
    public string ScriptAnalyze => T("script.analyze");
    public string ProjectsTitle => T("project.title");
    public string NewProjectTitle => T("project.new");
    public string FavoritesTitle => T("nav.favorites");
    public string DownloadsTitle => T("download.title");
    public string HistoryTitle => T("search.history");
    public string SettingsTitle => T("nav.settings");
    public string SourcesTitle => T("settings.sourcesProviders");
    public string ApiExplanation => T("settings.optionalAPIExplanation");
    public string PrivacyTitle => T("settings.privacy");
    public string PrivacyBody => T("settings.privacyBody");
    public string PreviewText => T("media.preview");
    public string FavoriteText => T("media.favorite");
    public string DownloadText => T("media.download");
    public string OpenSourceText => T("media.openSource");
    public string AllText => T("common.all");
    public string VideoText => T("common.video");
    public string ImageText => T("common.image");
    public string AudioText => T("common.audio");
    public string LandscapeText => T("media.landscape");
    public string PortraitText => T("media.portrait");
    public string SquareText => T("media.square");
    public string UnderMinuteText => T("filter.underMinute");
    public string OneToFiveText => T("filter.oneToFive");
    public string FiveToTwentyText => T("filter.fiveToTwenty");
    public string OverTwentyText => T("filter.overTwenty");
    public string LicenseKnownText => T("license.knownOnly");
    public string LicenseOpenText => T("license.openlyLicensed");
    public string LicensePublicDomainText => T("license.publicDomain");
    public string LicenseUnknownText => T("license.unknown");
    public string LicenseSafeText => T("license.safe");
    public string LicenseAttributionText => T("license.attribution");
    public string LicenseRestrictedText => T("license.restricted");
    public string SortRelevanceText => T("sort.relevance");
    public string SortNewestText => T("sort.newest");
    public string SortResolutionText => T("sort.resolution");
    public string SortDurationText => T("sort.duration");
    public string DeleteText => T("common.delete");
    public string CancelText => T("common.cancel");
    public string RetryText => T("common.retry");
    public string RetryFailedText => T("download.retryFailed");
    public string OpenFolderText => T("download.openFolder");
    public string OpenFileText => T("download.openFile");
    public string ClearHistoryText => T("history.clear");
    public string SearchAgainText => T("history.research");
    public string SaveText => T("common.save");
    public string RemoveKeyText => T("settings.removeAPIKey");
    public string TestConnectionText => T("settings.testConnection");
    public string DownloadFolderText => T("settings.downloadRoot");
    public string ChooseText => T("settings.choose");
    public string DownloadableOnlyText => T("filter.downloadableOnly");
    public string YearFromText => T("filter.yearFrom");
    public string YearToText => T("filter.yearTo");
    public string SelectAllVisibleText => T("selection.selectAllVisible");
    public string DownloadSelectedText => T("selection.downloadSelected");
    public string AddToProjectText => T("selection.addToProject");
    public string CopySourceInfoText => T("selection.copySourceInfo");
    public string ClearSelectionText => T("selection.clear");
    public string CopySourceText => T("media.copySource");
    public string CopyAttributionText => T("media.copyAttribution");
    public string SelectionStatus => _localization.Text("selection.count", SelectedCount);
    public string OpenOfficialSearchText => T("provider.openOfficialSearch");

    public void SetLanguage(string language) => _localization.SetLanguage(language);

    public void OpenOfficialSearch(string provider)
    {
        var query = Uri.EscapeDataString(string.IsNullOrWhiteSpace(Query) ? "history" : Query.Trim());
        var url = provider switch
        {
            "nasa" => $"https://images.nasa.gov/search?q={query}",
            "libraryOfCongress" => $"https://www.loc.gov/film-and-videos/?q={query}",
            "nationalArchives" => $"https://catalog.archives.gov/search?q={query}",
            "europeana" => $"https://www.europeana.eu/en/search?query={query}",
            _ => null
        };
        ShellService.OpenUrl(url);
    }

    public void SaveApiKey(string provider, string value)
    {
        var clean = value.Trim();
        if (clean.Length == 0) return;
        _credentials.Save(provider, clean);
        RefreshProviderModes();
    }

    public void RemoveApiKey(string provider)
    {
        _credentials.Remove(provider);
        RefreshProviderModes();
    }

    public async Task<string> TestProviderAsync(string provider)
    {
        var option = Providers.First(x => x.Id == provider);
        option.Status = T("settings.connecting");
        try
        {
            if (provider == "youtube" && string.IsNullOrWhiteSpace(ReadCredential(provider)))
            {
                _ = await _ytDlp.SearchAsync("bank", 1, CancellationToken.None);
                option.Status = T("settings.connectionSuccess");
                return option.Status;
            }
            if (provider is "nationalArchives" or "europeana" &&
                string.IsNullOrWhiteSpace(ReadCredential(provider)))
            {
                option.Status = T("provider.limitedMode");
                return option.Status;
            }
            var response = await _core.SendAsync(new CoreRequest
            {
                Action = "providerTest", ProviderIDs = [provider],
                ApiKeys = CredentialDictionary(provider), Language = _settings.Current.Language
            });
            option.Status = response.Success ? T("settings.connectionSuccess") :
                response.ErrorMessage ?? T("settings.connectionFailed");
        }
        catch (Exception error) { option.Status = error.Message; }
        return option.Status;
    }

    public void ChooseDownloadRoot(string path)
    {
        if (string.IsNullOrWhiteSpace(path)) return;
        _settings.Current.DownloadRoot = path;
        _settings.Save();
        OnPropertyChanged(nameof(DownloadRoot));
    }

    private ProviderOption NewProvider(string id, string name) =>
        new(id, name, _settings.Current.EnabledProviders.Contains(id));

    private async Task SearchAsync()
    {
        var clean = Query.Trim();
        if (clean.Length == 0) { SearchStatus = T("search.enterQuery"); return; }
        _searchCancellation?.Cancel();
        _searchCancellation = new CancellationTokenSource();
        var cancellationToken = _searchCancellation.Token;
        IsSearching = true;
        Results.Clear(); SearchKeywords.Clear(); SelectedCount = 0;
        var selected = Providers.Where(x => x.Enabled).ToList();
        if (selected.Count == 0) { SearchStatus = T("search.noResults"); IsSearching = false; return; }
        SearchStatus = T("search.searchingOthers");
        try
        {
            var keywords = await _core.SendAsync(new CoreRequest
            {
                Action = "keywords", Query = clean, Language = _settings.Current.Language
            }, cancellationToken: cancellationToken);
            foreach (var keyword in keywords.Keywords ?? []) SearchKeywords.Add(keyword);
            var effectiveQuery = SearchKeywords.FirstOrDefault(x => x.IsEnabled)?.Text ?? clean;
            var tasks = selected.ToDictionary(option => option.Id, option => SearchProviderAsync(option, effectiveQuery, cancellationToken));
            var pending = tasks.Values.ToList();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            while (pending.Count > 0)
            {
                var completed = await Task.WhenAny(pending);
                pending.Remove(completed);
                var batch = await completed;
                foreach (var asset in batch.Assets)
                    if (seen.Add(asset.StableId))
                    {
                        asset.PropertyChanged += ResultPropertyChanged;
                        Results.Add(asset);
                    }
                SearchStatus = pending.Count > 0
                    ? $"{T("search.searchingOthers")}  {Results.Count}"
                    : _localization.Text("search.found", Results.Count);
            }
            await _core.SendAsync(new CoreRequest
            {
                Action = "addHistory", Query = clean, Keywords = SearchKeywords.Select(x => x.Text).ToArray(),
                ProviderIDs = selected.Select(x => x.Id).ToArray(), ProjectID = CurrentProject?.Id.ToString(),
                ResultCount = Results.Count, Language = _settings.Current.Language
            }, cancellationToken: cancellationToken);
            await LoadDatabaseAsync();
        }
        catch (OperationCanceledException) { SearchStatus = T("search.stopped"); }
        catch (Exception error) { SearchStatus = error.Message; }
        finally { IsSearching = false; }
    }

    private async Task<ProviderBatch> SearchProviderAsync(
        ProviderOption option,
        string query,
        CancellationToken cancellationToken)
    {
        try
        {
            if (option.Id == "youtube" && string.IsNullOrWhiteSpace(ReadCredential("youtube")))
            {
                var raw = await _ytDlp.SearchAsync(query, 16, cancellationToken);
                var mapped = await _core.SendAsync(new CoreRequest
                {
                    Action = "mapYTDLPSearch", Query = query, PageSize = 12,
                    ExternalToolOutputBase64 = Convert.ToBase64String(raw), Language = _settings.Current.Language
                }, cancellationToken: cancellationToken);
                option.Status = T("provider.bestEffort");
                return new ProviderBatch
                {
                    Provider = "youtube", DisplayName = "YouTube", Mode = "ytDLP",
                    State = new ProviderState { Availability = "bestEffort", Mode = "ytDLP" },
                    Assets = mapped.Assets ?? []
                };
            }
            var response = await _core.SendAsync(new CoreRequest
            {
                Action = "search", Query = query, MediaType = MediaType, Orientation = Orientation,
                Resolution = Resolution, Duration = Duration,
                YearFrom = int.TryParse(YearFrom, out var from) ? from : null,
                YearTo = int.TryParse(YearTo, out var to) ? to : null,
                DownloadableOnly = DownloadableOnly, PageSize = 20, ProviderIDs = [option.Id],
                ApiKeys = CredentialDictionary(option.Id), Language = _settings.Current.Language
            }, cancellationToken: cancellationToken);
            var batch = response.ProviderBatches?.FirstOrDefault() ?? new ProviderBatch
            {
                Provider = option.Id, DisplayName = option.DisplayName,
                State = new ProviderState { Availability = "unavailable", Message = response.ErrorMessage }
            };
            option.Status = batch.State.Message ?? AvailabilityText(batch.State.Availability);
            option.Mode = ModeText(batch.Mode);
            return batch;
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception error)
        {
            option.Status = error.Message;
            return new ProviderBatch
            {
                Provider = option.Id, DisplayName = option.DisplayName,
                State = new ProviderState { Availability = "unavailable", Message = error.Message }
            };
        }
    }

    private async Task ToggleFavoriteAsync(MediaAsset? asset)
    {
        if (asset is null) return;
        await _core.SendAsync(new CoreRequest
        {
            Action = "toggleFavorite", Asset = asset, ProjectID = CurrentProject?.Id.ToString(),
            Language = _settings.Current.Language
        });
        await LoadDatabaseAsync();
    }

    private void EnqueueDownload(MediaAsset? asset)
    {
        if (asset is null || !asset.Downloadable) return;
        if (DownloadRecords.Any(record =>
                record.StableAssetID.Equals(asset.StableId, StringComparison.OrdinalIgnoreCase) &&
                File.Exists(record.LocalPath)))
        {
            CurrentPage = "downloads";
            return;
        }
        Downloads.Enqueue(asset, CurrentProject?.Id, CurrentProject?.Name ?? T("common.uncategorized"));
        CurrentPage = "downloads";
    }

    private void ResultPropertyChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (args.PropertyName != nameof(MediaAsset.IsSelected)) return;
        SelectedCount = Results.Count(asset => asset.IsSelected);
    }

    private void SelectAllVisible()
    {
        foreach (var asset in ResultsView.Cast<MediaAsset>()) asset.IsSelected = true;
    }

    private void ClearSelection()
    {
        foreach (var asset in Results) asset.IsSelected = false;
    }

    private void DownloadSelected()
    {
        var selected = Results.Where(asset => asset.IsSelected && asset.Downloadable).ToArray();
        foreach (var asset in selected)
            Downloads.Enqueue(asset, CurrentProject?.Id, CurrentProject?.Name ?? T("common.uncategorized"));
        if (selected.Length > 0) CurrentPage = "downloads";
    }

    private async Task AddSelectedToProjectAsync()
    {
        if (CurrentProject is null) return;
        foreach (var asset in Results.Where(asset => asset.IsSelected))
            await _core.SendAsync(new CoreRequest
            {
                Action = "addFavorite", Asset = asset, ProjectID = CurrentProject.Id.ToString(),
                Language = _settings.Current.Language
            });
        await LoadDatabaseAsync();
    }

    private async Task CreateProjectFromSelectionAsync()
    {
        if (string.IsNullOrWhiteSpace(NewProjectName) || SelectedCount == 0) return;
        await CreateProjectAsync();
        await AddSelectedToProjectAsync();
    }

    private async Task CopySelectedSourcesAsync()
    {
        var parts = new List<string>();
        foreach (var asset in Results.Where(asset => asset.IsSelected))
        {
            var response = await _core.SendAsync(new CoreRequest
            {
                Action = "formatSource", Asset = asset, Language = _settings.Current.Language
            });
            if (!string.IsNullOrWhiteSpace(response.Text)) parts.Add(response.Text);
        }
        if (parts.Count > 0) Clipboard.SetText(string.Join("\n\n---\n\n", parts));
    }

    private async Task CopyTextAsync(MediaAsset? asset, string action)
    {
        if (asset is null) return;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = action, Asset = asset, Language = _settings.Current.Language
        });
        if (!string.IsNullOrWhiteSpace(response.Text)) Clipboard.SetText(response.Text);
    }

    private async Task CreateProjectAsync()
    {
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "addProject", ProjectName = NewProjectName, Language = _settings.Current.Language
        });
        NewProjectName = "";
        ApplyDatabase(response.Database);
        CurrentProject = response.Project;
    }

    private async Task DeleteProjectAsync(ProjectRecord? project)
    {
        if (project is null) return;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "deleteProject", ProjectID = project.Id.ToString(), Language = _settings.Current.Language
        });
        if (CurrentProject?.Id == project.Id) CurrentProject = null;
        ApplyDatabase(response.Database);
    }

    private async Task SaveProjectAsync()
    {
        if (CurrentProject is null) return;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "updateProject", ProjectID = CurrentProject.Id.ToString(),
            ProjectName = ProjectEditName, ProjectScript = ScriptText,
            Language = _settings.Current.Language
        });
        ApplyDatabase(response.Database);
    }

    private async Task SearchHistoryAsync(SearchHistoryRecord? history)
    {
        if (history is null) return;
        Query = history.OriginalQuery;
        CurrentPage = "search";
        await SearchAsync();
    }

    private async Task ClearHistoryAsync()
    {
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "clearHistory", Language = _settings.Current.Language
        });
        ApplyDatabase(response.Database);
    }

    private async Task DeleteHistoryAsync(SearchHistoryRecord? history)
    {
        if (history is null) return;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "deleteHistory", RecordID = history.Id.ToString(),
            Language = _settings.Current.Language
        });
        ApplyDatabase(response.Database);
    }

    private async Task AnalyzeScriptAsync()
    {
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "splitScript", Query = ScriptText, Language = _settings.Current.Language
        });
        ScriptSegments.Clear();
        foreach (var segment in response.Segments ?? []) ScriptSegments.Add(segment);
    }

    private async Task RemoveDownloadRecordAsync(DownloadRecord? record)
    {
        if (record is null) return;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "deleteDownload", RecordID = record.Id.ToString(),
            Language = _settings.Current.Language
        });
        ApplyDatabase(response.Database);
    }

    private async Task LoadDatabaseAsync()
    {
        try
        {
            var response = await _core.SendAsync(new CoreRequest
            {
                Action = "databaseSnapshot", Language = _settings.Current.Language
            });
            ApplyDatabase(response.Database);
        }
        catch { }
    }

    private void ApplyDatabase(PersistentDatabase? database)
    {
        if (database is null) return;
        Replace(Projects, database.Projects.OrderByDescending(x => x.UpdatedAt));
        Replace(Favorites, database.Favorites.OrderByDescending(x => x.SavedAt));
        Replace(History, database.History.OrderByDescending(x => x.SearchedAt));
        Replace(DownloadRecords, database.Downloads.OrderByDescending(x => x.DownloadedAt));
        if (CurrentProject is not null) CurrentProject = Projects.FirstOrDefault(x => x.Id == CurrentProject.Id);
    }

    private static void Replace<T>(ObservableCollection<T> target, IEnumerable<T> values)
    {
        target.Clear();
        foreach (var value in values) target.Add(value);
    }

    private bool MatchesProject(Guid? projectId) => CurrentProject is null || projectId == CurrentProject.Id;

    private bool MatchesFilters(MediaAsset asset)
    {
        if (MediaType != "all" && asset.MediaType != MediaType) return false;
        if (DownloadableOnly && !asset.IsDirectlyDownloadable) return false;
        if (Orientation != "all" && AssetOrientation(asset) != Orientation) return false;
        var minimumHeight = Resolution switch { "hd720" => 720, "fullHD" => 1080, "uhd4K" => 2160, _ => 0 };
        if (minimumHeight > 0 && Math.Min(asset.Width ?? 0, asset.Height ?? 0) < minimumHeight) return false;
        if (!DurationMatches(asset.Duration)) return false;
        if (int.TryParse(YearFrom, out var from) && (asset.PublishedDate?.Year ?? int.MinValue) < from) return false;
        if (int.TryParse(YearTo, out var to) && (asset.PublishedDate?.Year ?? int.MaxValue) > to) return false;
        return LicenseFilter switch
        {
            "knownOnly" => asset.RightsKnown,
            "openlyLicensed" => asset.RightsKnown && asset.OpenLicense,
            "publicDomain" => asset.RightsKnown && asset.PublicDomain,
            _ => true
        };
    }

    private bool DurationMatches(double? value) => Duration switch
    {
        "underMinute" => value is >= 0 and < 60,
        "oneToFive" => value is >= 60 and < 300,
        "fiveToTwenty" => value is >= 300 and < 1200,
        "overTwenty" => value is >= 1200,
        _ => true
    };

    private static string AssetOrientation(MediaAsset asset)
    {
        if (asset.Width is not > 0 || asset.Height is not > 0) return "unknown";
        var ratio = asset.Width.Value / (double)asset.Height.Value;
        if (ratio > 1.12) return "landscape";
        if (ratio < 0.88) return "portrait";
        return "square";
    }

    private static string Digits(string value) => new(value.Where(char.IsDigit).Take(4).ToArray());

    private void ApplySort()
    {
        ResultsView.SortDescriptions.Clear();
        var property = Sort switch
        {
            "newest" => nameof(MediaAsset.SortPublishedDate),
            "resolution" => nameof(MediaAsset.PixelCount),
            "duration" => nameof(MediaAsset.SortDuration),
            _ => nameof(MediaAsset.RelevanceScore)
        };
        ResultsView.SortDescriptions.Add(new SortDescription(property, ListSortDirection.Descending));
    }

    private Dictionary<string, string> CredentialDictionary(string provider)
    {
        var value = ReadCredential(provider);
        return string.IsNullOrWhiteSpace(value) ? [] : new Dictionary<string, string> { [provider] = value };
    }

    private string ReadCredential(string provider)
    {
        try { return _credentials.Read(provider); }
        catch { return ""; }
    }

    private void RefreshProviderModes()
    {
        foreach (var provider in Providers)
        {
            var hasKey = provider.SupportsApiKey && !string.IsNullOrWhiteSpace(ReadCredential(provider.Id));
            provider.Mode = hasKey
                ? $"{T("provider.mode.officialAPI")} · ✓ {T("settings.recommended")}" : provider.Id switch
            {
                "pexels" or "pixabay" => T("provider.mode.directSearch"),
                "youtube" => T("provider.mode.ytDLP"),
                "nasa" or "libraryOfCongress" => T("provider.mode.publicAPI"),
                "nationalArchives" or "europeana" => T("provider.mode.limited"),
                _ => T("provider.mode.publicInterface")
            };
            provider.Status = hasKey ? T("settings.configured") :
                provider.Id is "nationalArchives" or "europeana" ? T("provider.limitedMode") :
                provider.Id is "pexels" or "pixabay" or "youtube" ? T("provider.bestEffort") :
                provider.Id is "nasa" or "libraryOfCongress" ? T("provider.noKeyRequired") :
                T("provider.available");
            var values = provider.Id is "nationalArchives" or "europeana" && !hasKey
                ? new[] { T("provider.openOfficialSearch") }
                : new[] { T("capability.search"), T("capability.preview"), T("capability.metadata"),
                    T("capability.rights"), T("capability.download") };
            provider.Capabilities = _localization.Text("settings.capabilities", string.Join(" · ", values));
        }
    }

    private string AvailabilityText(string value) => value switch
    {
        "apiConnected" => T("provider.apiConnected"), "bestEffort" => T("provider.bestEffort"),
        "publicAPI" => T("provider.publicAPI"), "limitedMode" => T("provider.limitedMode"),
        "rateLimited" => T("provider.rateLimited"), "temporarilyBlocked" => T("provider.temporarilyBlocked"),
        "available" => T("provider.available"), _ => T("provider.unavailable")
    };

    private string ModeText(string value) => value switch
    {
        "officialAPI" => $"{T("provider.mode.officialAPI")} · ✓ {T("settings.recommended")}",
        "publicAPI" => T("provider.mode.publicAPI"), "limited" => T("provider.mode.limited"),
        "directSearch" => T("provider.mode.directSearch"),
        "ytDLP" => T("provider.mode.ytDLP"), _ => T("provider.mode.publicInterface")
    };

    private void RefreshLanguage()
    {
        OnPropertyChanged(null);
        RefreshProviderModes();
        Downloads.RefreshLocalizedStatus();
        SearchStatus = T("search.initialStatus");
    }
}
