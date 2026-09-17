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
    private string _searchScope = "media";
    private string _searchStatus = "";
    private bool _isSearching;
    private bool _isLoadingMore;
    private string _lastEffectiveQuery = "";
    private string[] _lastSearchQueries = [];
    private readonly Dictionary<string, ProviderContinuation> _continuations = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, ProviderContinuation> _researchContinuations = new(StringComparer.OrdinalIgnoreCase);
    private string _lastResearchQuery = "";
    private string _mediaType = "video";
    private string? _lastRequestedMediaType;
    private bool _refreshMediaTypeAfterSearch;
    private bool _suppressMediaTypeSearch;
    private string _orientation = "all";
    private string _resolution = "all";
    private string _duration = "all";
    private string _licenseFilter = "all";
    private string _yearFrom = "";
    private string _yearTo = "";
    private bool _downloadableOnly;
    private int _selectedCount;
    private string _sort = "relevance";
    private readonly List<MediaAsset> _candidateResults = [];
    private ProjectRecord? _currentProject;
    private string _newProjectName = "";
    private string _projectEditName = "";
    private string _scriptText = "";
    private string _linkInput = "";
    private string _linkStatus = "";
    private bool _isLinkAnalyzing;
    private string _keywordSourceQuery = "";
    private string _clipboardSuggestion = "";
    private readonly ClipboardSuggestionSession _clipboardSession = new();
    private bool _isUpdateChecking;
    private string _updateStatusCode = "";
    private readonly UpdateCheckSession _updateSession = new();
    private bool _showAllSearchLanguages;
    private RightsAuditReport? _rightsAudit;
    private string _selectedRightsAuditFilter = "all";
    private string _projectActionStatus = "";
    private bool _isProjectWorking;
    private bool _isCommandPaletteOpen;
    private bool _isGlobalSearchOpen;
    private string _commandPaletteQuery = "";
    private string _workspaceQuery = "";
    private string _workspaceStatus = "";
    private CancellationTokenSource? _workspaceSearchCancellation;
    private static readonly SemaphoreSlim SearchNetworkLimit = new(12, 12);
    private CancellationTokenSource? _duplicateCancellation;
    private bool _showAllDuplicateResults;
    private string _searchDuplicateSummary = "";

    public MainViewModel()
    {
        _localization = new LocalizationService(_settings);
        _localization.LanguageChanged += (_, _) => RefreshLanguage();
        Downloads = new DownloadQueueService(_core, _settings, _ytDlp, _localization);
        WorkspaceSearchResultsView = CollectionViewSource.GetDefaultView(WorkspaceSearchResults);
        WorkspaceSearchResultsView.GroupDescriptions.Add(
            new PropertyGroupDescription(nameof(WorkspaceSearchEntry.SectionTitle)));
        Downloads.DownloadCompleted += (_, _) => _ = LoadDatabaseAsync();
        ResultsView = CollectionViewSource.GetDefaultView(Results);
        ResultsView.Filter = value => value is MediaAsset asset && MatchesFilters(asset);
        _showAllDuplicateResults = !_settings.Current.CollapseDuplicateGroups;
        ApplySort();
        SearchKeywordsView = CollectionViewSource.GetDefaultView(SearchKeywords);
        SearchKeywordsView.Filter = value => value is SearchKeyword keyword &&
            (ShowAllSearchLanguages || keyword.Origin == "input" || keyword.Language == "en");
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
            NewProvider("nationalArchives", "National Archives"), NewProvider("europeana", "Europeana"),
            NewProvider("peertube", "PeerTube / SepiaSearch"), NewProvider("videvo", "Videvo"),
            NewProvider("videezy", "Videezy"), NewProvider("mixkit", "Mixkit"),
            NewProvider("coverr", "Coverr"), NewProvider("vimeo", "Vimeo"),
            NewProvider("openverse", "Openverse"), NewProvider("dailymotion", "Dailymotion"),
            NewProvider("dareful", "Dareful"), NewProvider("mazwai", "Mazwai"),
            NewProvider("dvids", "DVIDS"), NewProvider("britishPathe", "British Pathé"),
            NewProvider("esa", "ESA Multimedia")
        });
        foreach (var provider in Providers)
            provider.PropertyChanged += (_, args) =>
            {
                if (args.PropertyName != nameof(ProviderOption.Enabled)) return;
                if (provider.Enabled) _settings.Current.EnabledProviders.Add(provider.Id);
                else _settings.Current.EnabledProviders.Remove(provider.Id);
                _settings.Save();
                ResultsView.Refresh();
                ScheduleDuplicateReview();
            };
        ResearchProviders = new ObservableCollection<ProviderOption>(new[]
        {
            new ProviderOption("wikipedia", "Wikipedia", true),
            new ProviderOption("wikidata", "Wikidata", true),
            new ProviderOption("metropolitanMuseum", "The Metropolitan Museum of Art", true),
            new ProviderOption("artInstituteChicago", "Art Institute of Chicago", true),
            new ProviderOption("crossref", "Crossref", true),
            new ProviderOption("gdelt", "GDELT", true)
        });
        NavigateCommand = new RelayCommand(page => CurrentPage = page?.ToString() ?? "search");
        SearchCommand = new AsyncRelayCommand(_ => SearchAsync(), _ => !IsSearching);
        AddSearchKeywordCommand = new RelayCommand(_ =>
        {
            SearchKeywords.Add(new SearchKeyword
            {
                Id = Guid.NewGuid(), Text = "", IsEnabled = true,
                Language = _settings.Current.Language, Origin = "userAdded", Priority = 99
            });
            SearchKeywordsView.Refresh();
        });
        RemoveSearchKeywordCommand = new RelayCommand(value =>
        {
            if (value is SearchKeyword keyword) SearchKeywords.Remove(keyword);
            SearchKeywordsView.Refresh();
        });
        ToggleSearchLanguagesCommand = new RelayCommand(_ =>
            ShowAllSearchLanguages = !ShowAllSearchLanguages);
        RegenerateKeywordsCommand = new AsyncRelayCommand(_ => RegenerateKeywordsAsync());
        LoadMoreCommand = new AsyncRelayCommand(_ => LoadMoreAsync(), _ => CanLoadMore && !IsSearching && !IsLoadingMore);
        StopSearchCommand = new RelayCommand(_ =>
        {
            _refreshMediaTypeAfterSearch = false;
            _searchCancellation?.Cancel();
        }, _ => IsSearching);
        OpenSourceCommand = new RelayCommand(asset => ShellService.OpenUrl((asset as MediaAsset)?.SourcePageURL));
        PreviewCommand = new RelayCommand(asset => PreviewRequested?.Invoke(asset as MediaAsset));
        FavoriteCommand = new AsyncRelayCommand(asset => ToggleFavoriteAsync(asset as MediaAsset));
        DownloadCommand = new RelayCommand(asset => EnqueueDownload(asset as MediaAsset));
        DownloadEditingCompatibleCommand = new RelayCommand(asset =>
            EnqueueDownload(WithEditingOutput(asset as MediaAsset, "editingCompatibleMP4")));
        DownloadAudioOnlyCommand = new RelayCommand(asset =>
            EnqueueDownload(WithEditingOutput(asset as MediaAsset, "audioOnly")));
        SelectAllVisibleCommand = new RelayCommand(_ => SelectAllVisible());
        ClearSelectionCommand = new RelayCommand(_ => ClearSelection());
        DownloadSelectedCommand = new RelayCommand(_ => DownloadSelected());
        AddSelectedToProjectCommand = new AsyncRelayCommand(_ => AddSelectedToProjectAsync(),
            _ => CurrentProject is not null && SelectedCount > 0);
        CreateProjectFromSelectionCommand = new AsyncRelayCommand(_ => CreateProjectFromSelectionAsync());
        CopySelectedSourceCommand = new AsyncRelayCommand(_ => CopySelectedSourcesAsync());
        CopySourceCommand = new AsyncRelayCommand(asset => CopyTextAsync(asset as MediaAsset, "formatSource"));
        CopyAttributionCommand = new AsyncRelayCommand(asset => CopyTextAsync(asset as MediaAsset, "formatAttribution"));
        AddResearchNoteCommand = new AsyncRelayCommand(record => AddResearchNoteAsync(record as ResearchRecord), _ => CurrentProject is not null);
        CopyResearchCitationCommand = new RelayCommand(record =>
        {
            if (record is ResearchRecord value) Clipboard.SetText(value.Citation);
        });
        FindRelatedMediaCommand = new AsyncRelayCommand(record => FindRelatedMediaAsync(record as ResearchRecord));
        AddResearchAsMediaCommand = new AsyncRelayCommand(record => AddResearchAsMediaAsync(record as ResearchRecord));
        OpenResearchSourceCommand = new RelayCommand(record =>
            ShellService.OpenUrl((record as ResearchRecord)?.CanonicalURL));
        SaveResearchNoteCommand = new AsyncRelayCommand(reference => SaveResearchNoteAsync(reference as ResearchReferenceRecord));
        RefreshResearchMetadataCommand = new AsyncRelayCommand(reference => RefreshResearchMetadataAsync(reference as ResearchReferenceRecord));
        DeleteResearchNoteCommand = new AsyncRelayCommand(reference => DeleteResearchNoteAsync(reference as ResearchReferenceRecord));
        CreateProjectCommand = new AsyncRelayCommand(_ => CreateProjectAsync());
        ClearProjectCommand = new RelayCommand(_ => CurrentProject = null);
        ClearFiltersCommand = new RelayCommand(_ => ClearFilters());
        SaveProjectCommand = new AsyncRelayCommand(_ => SaveProjectAsync(), _ => CurrentProject is not null);
        DeleteProjectCommand = new AsyncRelayCommand(project => DeleteProjectAsync(project as ProjectRecord));
        RefreshRightsAuditCommand = new AsyncRelayCommand(_ => RefreshRightsAuditAsync(), _ => CurrentProject is not null && !IsProjectWorking);
        FindDuplicatesCommand = new AsyncRelayCommand(_ => FindDuplicatesAsync(), _ => CurrentProject is not null && !IsProjectWorking);
        MarkReviewedCommand = new AsyncRelayCommand(value => SetReviewedAsync(value as RightsAuditEntry, true));
        KeepBothCommand = new AsyncRelayCommand(value => SetDuplicateDecisionAsync(value as DuplicateGroup, "keepBoth"));
        NotDuplicateCommand = new AsyncRelayCommand(value => SetDuplicateDecisionAsync(value as DuplicateGroup, "notDuplicate"));
        ResetDuplicateDecisionsCommand = new AsyncRelayCommand(_ => ResetDuplicateDecisionsAsync(), _ => CurrentProject is not null);
        RemoveAssetFromProjectCommand = new AsyncRelayCommand(value => RemoveAssetFromProjectAsync(value as ProjectAssetItem));
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
        PasteLinkCommand = new RelayCommand(_ => LinkInput = Clipboard.ContainsText() ? Clipboard.GetText() : "");
        AnalyzeLinksCommand = new AsyncRelayCommand(_ => AnalyzeLinksAsync(), _ => !IsLinkAnalyzing);
        DownloadLinkSelectedCommand = new RelayCommand(_ => DownloadLinkSelected());
        OpenLinkOriginalCommand = new RelayCommand(item =>
            ShellService.OpenUrl((item as LinkDownloadItem)?.Analysis?.OriginalURL));
        ResetClipCommand = new RelayCommand(value =>
        {
            if (value is not LinkDownloadItem item) return;
            item.ClipStart = "00:00:00";
            item.InitializeClipEnd();
        });
        AnalyzeClipboardCommand = new AsyncRelayCommand(_ => AnalyzeClipboardAsync());
        IgnoreClipboardCommand = new RelayCommand(_ => IgnoreClipboard());
        DisableClipboardCommand = new RelayCommand(_ =>
        {
            ClipboardDetectionEnabled = false;
            IgnoreClipboard();
        });
        OpenFeedbackCommand = new AsyncRelayCommand(value => OpenFeedbackAsync(value?.ToString()));
        CheckForUpdatesCommand = new AsyncRelayCommand(_ => CheckForUpdatesAsync(manual: true), _ => !IsUpdateChecking);
        ShowCommandPaletteCommand = new RelayCommand(_ => IsCommandPaletteOpen = true);
        CloseCommandPaletteCommand = new RelayCommand(_ => IsCommandPaletteOpen = false);
        ExecuteWorkspaceCommand = new AsyncRelayCommand(value => ExecuteWorkspaceCommandAsync(value?.ToString()));
        ShowGlobalSearchCommand = new RelayCommand(_ => IsGlobalSearchOpen = true);
        CloseGlobalSearchCommand = new RelayCommand(_ => IsGlobalSearchOpen = false);
        SearchWorkspaceCommand = new AsyncRelayCommand(_ => SearchWorkspaceAsync());
        OpenWorkspaceResultCommand = new AsyncRelayCommand(value => OpenWorkspaceResultAsync(value as WorkspaceSearchEntry));
        SaveSearchCommand = new AsyncRelayCommand(_ => SaveCurrentSearchAsync(), _ => !string.IsNullOrWhiteSpace(Query));
        RunSavedSearchCommand = new AsyncRelayCommand(value => RunSavedSearchAsync(value as SavedSearchRecord));
        RenameSavedSearchCommand = new AsyncRelayCommand(value => RenameSavedSearchAsync(value as SavedSearchRecord));
        DeleteSavedSearchCommand = new AsyncRelayCommand(value => DeleteSavedSearchAsync(value as SavedSearchRecord));
        DuplicateSavedSearchCommand = new AsyncRelayCommand(value => DuplicateSavedSearchAsync(value as SavedSearchRecord));
        TestWorkspaceProviderCommand = new AsyncRelayCommand(value => TestWorkspaceProviderAsync(value?.ToString()));
        TestAllWorkspaceProvidersCommand = new AsyncRelayCommand(_ => TestAllWorkspaceProvidersAsync());
        OpenSmartCollectionCommand = new RelayCommand(value =>
            CurrentPage = (value as WorkspaceSmartCollection)?.Destination ?? "workspace");
        RefreshWorkspaceCommands();
        RefreshProviderModes();
        SearchStatus = T("search.initialStatus");
        _ = LoadDatabaseAsync();
    }

    public event Action<MediaAsset?>? PreviewRequested;
    public event Action<AppReleaseInfo>? UpdateAvailable;
    public event Action? FocusSearchRequested;
    public DownloadQueueService Downloads { get; }
    public ObservableCollection<ProviderOption> Providers { get; }
    public ObservableCollection<ProviderOption> ResearchProviders { get; }
    public ObservableCollection<MediaAsset> Results { get; } = [];
    public ObservableCollection<ResearchRecord> ResearchResults { get; } = [];
    public ObservableCollection<ResearchReferenceRecord> ResearchReferences { get; } = [];
    public ICollectionView ResultsView { get; }
    public ObservableCollection<SearchKeyword> SearchKeywords { get; } = [];
    public ICollectionView SearchKeywordsView { get; }
    public ObservableCollection<ProjectRecord> Projects { get; } = [];
    public ObservableCollection<SavedAssetRecord> Favorites { get; } = [];
    public ObservableCollection<SearchHistoryRecord> History { get; } = [];
    public ObservableCollection<DownloadRecord> DownloadRecords { get; } = [];
    public ICollectionView FavoritesView { get; }
    public ICollectionView HistoryView { get; }
    public ICollectionView DownloadRecordsView { get; }
    public ObservableCollection<string> ScriptSegments { get; } = [];
    public ObservableCollection<LinkDownloadItem> LinkItems { get; } = [];
    public ObservableCollection<DuplicateGroup> DuplicateGroups { get; } = [];
    public ObservableCollection<SearchDuplicateDisplayItem> SearchDuplicateItems { get; } = [];
    public string SearchDuplicateSummary
    {
        get => _searchDuplicateSummary;
        private set => Set(ref _searchDuplicateSummary, value);
    }
    public bool HasDuplicateGroups => HasMediaSearchScope && SearchDuplicateItems.Any(item => item.IsGroup);
    public bool HasGroupedDuplicateView => DetectSearchDuplicates && HasDuplicateGroups && !ShowAllDuplicateResults;
    public bool ShowAllDuplicateResults
    {
        get => _showAllDuplicateResults;
        set
        {
            if (!Set(ref _showAllDuplicateResults, value)) return;
            OnPropertyChanged(nameof(HasGroupedDuplicateView));
        }
    }
    public bool DetectSearchDuplicates
    {
        get => _settings.Current.DetectSearchDuplicates;
        set
        {
            if (_settings.Current.DetectSearchDuplicates == value) return;
            _settings.Current.DetectSearchDuplicates = value;
            _settings.Save();
            OnPropertyChanged();
            ScheduleDuplicateReview();
        }
    }
    public bool CollapseDuplicateGroups
    {
        get => _settings.Current.CollapseDuplicateGroups;
        set
        {
            if (_settings.Current.CollapseDuplicateGroups == value) return;
            _settings.Current.CollapseDuplicateGroups = value;
            _settings.Save();
            OnPropertyChanged();
            ShowAllDuplicateResults = !value;
        }
    }
    public string DuplicateSettingsTitle => T("duplicate.settingsTitle");
    public string DuplicateDetectSettingText => T("duplicate.detectSetting");
    public string DuplicateCollapseSettingText => T("duplicate.collapseSetting");
    public string DuplicateSettingsDetail => T("duplicate.settingsDetail");
    public string DuplicateAllResultsText => T("duplicate.allResults");
    public ObservableCollection<SavedSearchRecord> SavedSearches { get; } = [];
    public ObservableCollection<ProviderHealthRecord> ProviderHealth { get; } = [];
    public ObservableCollection<WorkspaceSearchEntry> WorkspaceSearchResults { get; } = [];
    public ICollectionView WorkspaceSearchResultsView { get; }
    public ObservableCollection<WorkspaceCommandItem> WorkspaceCommands { get; } = [];
    public ObservableCollection<WorkspaceCommandItem> WorkspaceShortcutReference { get; } = [];
    public ObservableCollection<WorkspaceSmartCollection> WorkspaceSmartCollections { get; } = [];

    public ICommand NavigateCommand { get; }
    public ICommand SearchCommand { get; }
    public ICommand AddSearchKeywordCommand { get; }
    public ICommand RemoveSearchKeywordCommand { get; }
    public ICommand RegenerateKeywordsCommand { get; }
    public ICommand ToggleSearchLanguagesCommand { get; }
    public ICommand LoadMoreCommand { get; }
    public ICommand StopSearchCommand { get; }
    public ICommand OpenSourceCommand { get; }
    public ICommand PreviewCommand { get; }
    public ICommand FavoriteCommand { get; }
    public ICommand DownloadCommand { get; }
    public ICommand DownloadEditingCompatibleCommand { get; }
    public ICommand DownloadAudioOnlyCommand { get; }
    public ICommand SelectAllVisibleCommand { get; }
    public ICommand ClearSelectionCommand { get; }
    public ICommand DownloadSelectedCommand { get; }
    public ICommand AddSelectedToProjectCommand { get; }
    public ICommand CreateProjectFromSelectionCommand { get; }
    public ICommand CopySelectedSourceCommand { get; }
    public ICommand CopySourceCommand { get; }
    public ICommand CopyAttributionCommand { get; }
    public ICommand AddResearchNoteCommand { get; }
    public ICommand CopyResearchCitationCommand { get; }
    public ICommand FindRelatedMediaCommand { get; }
    public ICommand AddResearchAsMediaCommand { get; }
    public ICommand OpenResearchSourceCommand { get; }
    public ICommand SaveResearchNoteCommand { get; }
    public ICommand RefreshResearchMetadataCommand { get; }
    public ICommand DeleteResearchNoteCommand { get; }
    public ICommand CreateProjectCommand { get; }
    public ICommand ClearProjectCommand { get; }
    public ICommand ClearFiltersCommand { get; }
    public ICommand SaveProjectCommand { get; }
    public ICommand DeleteProjectCommand { get; }
    public ICommand RefreshRightsAuditCommand { get; }
    public ICommand FindDuplicatesCommand { get; }
    public ICommand MarkReviewedCommand { get; }
    public ICommand KeepBothCommand { get; }
    public ICommand NotDuplicateCommand { get; }
    public ICommand ResetDuplicateDecisionsCommand { get; }
    public ICommand RemoveAssetFromProjectCommand { get; }
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
    public ICommand PasteLinkCommand { get; }
    public ICommand AnalyzeLinksCommand { get; }
    public ICommand DownloadLinkSelectedCommand { get; }
    public ICommand OpenLinkOriginalCommand { get; }
    public ICommand ResetClipCommand { get; }
    public ICommand AnalyzeClipboardCommand { get; }
    public ICommand IgnoreClipboardCommand { get; }
    public ICommand DisableClipboardCommand { get; }
    public ICommand OpenFeedbackCommand { get; }
    public ICommand CheckForUpdatesCommand { get; }
    public ICommand ShowCommandPaletteCommand { get; }
    public ICommand CloseCommandPaletteCommand { get; }
    public ICommand ExecuteWorkspaceCommand { get; }
    public ICommand ShowGlobalSearchCommand { get; }
    public ICommand CloseGlobalSearchCommand { get; }
    public ICommand SearchWorkspaceCommand { get; }
    public ICommand OpenWorkspaceResultCommand { get; }
    public ICommand SaveSearchCommand { get; }
    public ICommand RunSavedSearchCommand { get; }
    public ICommand RenameSavedSearchCommand { get; }
    public ICommand DeleteSavedSearchCommand { get; }
    public ICommand DuplicateSavedSearchCommand { get; }
    public ICommand TestWorkspaceProviderCommand { get; }
    public ICommand TestAllWorkspaceProvidersCommand { get; }
    public ICommand OpenSmartCollectionCommand { get; }

    public string CurrentPage
    {
        get => _currentPage;
        set
        {
            if (!Set(ref _currentPage, value)) return;
            OnPropertyChanged(nameof(IsSearchPage)); OnPropertyChanged(nameof(IsScriptPage));
            OnPropertyChanged(nameof(IsWorkspacePage));
            OnPropertyChanged(nameof(IsProjectsPage)); OnPropertyChanged(nameof(IsFavoritesPage));
            OnPropertyChanged(nameof(IsDownloadsPage)); OnPropertyChanged(nameof(IsHistoryPage));
            OnPropertyChanged(nameof(IsSettingsPage));
            OnPropertyChanged(nameof(IsLinkDownloaderPage));
            OnPropertyChanged(nameof(IsFeedbackPage));
        }
    }
    public bool IsSearchPage => CurrentPage == "search";
    public bool IsWorkspacePage => CurrentPage == "workspace";
    public bool IsScriptPage => CurrentPage == "script";
    public bool IsProjectsPage => CurrentPage == "projects";
    public bool IsFavoritesPage => CurrentPage == "favorites";
    public bool IsDownloadsPage => CurrentPage == "downloads";
    public bool IsHistoryPage => CurrentPage == "history";
    public bool IsSettingsPage => CurrentPage == "settings";
    public bool IsLinkDownloaderPage => CurrentPage == "linkDownloader";
    public bool IsFeedbackPage => CurrentPage == "feedback";
    public string Query { get => _query; set => Set(ref _query, value); }
    public bool IsCommandPaletteOpen { get => _isCommandPaletteOpen; set => Set(ref _isCommandPaletteOpen, value); }
    public bool IsGlobalSearchOpen { get => _isGlobalSearchOpen; set => Set(ref _isGlobalSearchOpen, value); }
    public string CommandPaletteQuery
    {
        get => _commandPaletteQuery;
        set { if (Set(ref _commandPaletteQuery, value)) RefreshWorkspaceCommands(); }
    }
    public string WorkspaceQuery
    {
        get => _workspaceQuery;
        set
        {
            if (!Set(ref _workspaceQuery, value)) return;
            _ = ScheduleWorkspaceSearchAsync();
        }
    }
    public string WorkspaceStatus { get => _workspaceStatus; private set => Set(ref _workspaceStatus, value); }
    public string SearchScope
    {
        get => _searchScope;
        set
        {
            var normalized = value is "research" or "all" ? value : "media";
            if (!Set(ref _searchScope, normalized)) return;
            OnPropertyChanged(nameof(IsMediaSearchScope));
            OnPropertyChanged(nameof(IsResearchSearchScope));
            OnPropertyChanged(nameof(IsAllSearchScope));
            OnPropertyChanged(nameof(HasMediaSearchScope));
            OnPropertyChanged(nameof(HasResearchSearchScope));
            OnPropertyChanged(nameof(HasDuplicateGroups));
            OnPropertyChanged(nameof(HasGroupedDuplicateView));
        }
    }
    public bool IsMediaSearchScope => SearchScope == "media";
    public bool IsResearchSearchScope => SearchScope == "research";
    public bool IsAllSearchScope => SearchScope == "all";
    public bool HasMediaSearchScope => SearchScope != "research";
    public bool HasResearchSearchScope => SearchScope != "media";
    public bool ShowAllSearchLanguages
    {
        get => _showAllSearchLanguages;
        set
        {
            if (!Set(ref _showAllSearchLanguages, value)) return;
            SearchKeywordsView.Refresh();
            OnPropertyChanged(nameof(SearchLanguagesToggleText));
        }
    }
    public string SearchStatus { get => _searchStatus; set => Set(ref _searchStatus, value); }
    public bool IsSearching
    {
        get => _isSearching;
        private set
        {
            if (!Set(ref _isSearching, value)) return;
            (SearchCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
            (StopSearchCommand as RelayCommand)?.RaiseCanExecuteChanged();
            (LoadMoreCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
        }
    }
    public bool IsLoadingMore
    {
        get => _isLoadingMore;
        private set
        {
            if (!Set(ref _isLoadingMore, value)) return;
            OnPropertyChanged(nameof(CanLoadMore));
            (LoadMoreCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
        }
    }
    public bool CanLoadMore => _continuations.Count > 0 || _researchContinuations.Count > 0;
    public string MediaType
    {
        get => _mediaType;
        set
        {
            if (!Set(ref _mediaType, value)) return;
            ResultsView.Refresh();
            ScheduleDuplicateReview();
            if (_suppressMediaTypeSearch || _lastRequestedMediaType is null ||
                SearchScope == "research" || string.IsNullOrWhiteSpace(Query)) return;
            if (IsSearching)
            {
                _refreshMediaTypeAfterSearch = true;
                _searchCancellation?.Cancel();
            }
            else _ = SearchAsync();
        }
    }
    public string Orientation { get => _orientation; set { if (Set(ref _orientation, value)) { ResultsView.Refresh(); ScheduleDuplicateReview(); } } }
    public string Resolution { get => _resolution; set { if (Set(ref _resolution, value)) { ResultsView.Refresh(); ScheduleDuplicateReview(); } } }
    public string Duration { get => _duration; set { if (Set(ref _duration, value)) { ResultsView.Refresh(); ScheduleDuplicateReview(); } } }
    public string LicenseFilter { get => _licenseFilter; set { if (Set(ref _licenseFilter, value)) { ResultsView.Refresh(); ScheduleDuplicateReview(); } } }
    public string YearFrom { get => _yearFrom; set { if (Set(ref _yearFrom, Digits(value))) { ResultsView.Refresh(); ScheduleDuplicateReview(); } } }
    public string YearTo { get => _yearTo; set { if (Set(ref _yearTo, Digits(value))) { ResultsView.Refresh(); ScheduleDuplicateReview(); } } }
    public bool DownloadableOnly { get => _downloadableOnly; set { if (Set(ref _downloadableOnly, value)) { ResultsView.Refresh(); ScheduleDuplicateReview(); } } }
    public bool SmartExpansionEnabled
    {
        get => _settings.Current.SmartSearchExpansionEnabled;
        set
        {
            if (_settings.Current.SmartSearchExpansionEnabled == value) return;
            _settings.Current.SmartSearchExpansionEnabled = value;
            _settings.Save();
            OnPropertyChanged();
            _keywordSourceQuery = "";
        }
    }
    public string RelevanceMode
    {
        get => _settings.Current.SearchRelevanceMode;
        set
        {
            var normalized = value is "precise" or "broad" ? value : "balanced";
            if (_settings.Current.SearchRelevanceMode == normalized) return;
            _settings.Current.SearchRelevanceMode = normalized;
            _settings.Save();
            OnPropertyChanged();
            _ = RerankCurrentAsync();
        }
    }
    public bool ClipboardDetectionEnabled
    {
        get => _settings.Current.ClipboardMediaLinkDetectionEnabled;
        set
        {
            if (_settings.Current.ClipboardMediaLinkDetectionEnabled == value) return;
            _settings.Current.ClipboardMediaLinkDetectionEnabled = value;
            _settings.Save();
            OnPropertyChanged();
            if (!value) IgnoreClipboard();
        }
    }
    public bool HasClipboardSuggestion => !string.IsNullOrWhiteSpace(_clipboardSuggestion);
    public int ClipboardSuggestionCount => MediaLinkLines(_clipboardSuggestion).Count;
    public string ClipboardSuggestionText => ClipboardSuggestionCount == 1
        ? T("clipboard.mediaLinkDetected") : _localization.Text("clipboard.mediaLinksDetected", ClipboardSuggestionCount);
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
            ScheduleDuplicateReview();
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
            (AddResearchNoteCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
            FavoritesView.Refresh();
            HistoryView.Refresh();
            DownloadRecordsView.Refresh();
            OnPropertyChanged(nameof(CurrentResearchReferences));
            RefreshProjectDashboard();
            RightsAudit = null;
            DuplicateGroups.Clear();
            if (value is not null) _ = RefreshRightsAuditAsync();
        }
    }
    public string NewProjectName { get => _newProjectName; set => Set(ref _newProjectName, value); }
    public string ProjectEditName { get => _projectEditName; set => Set(ref _projectEditName, value); }
    public string ScriptText { get => _scriptText; set => Set(ref _scriptText, value); }
    public RightsAuditReport? RightsAudit
    {
        get => _rightsAudit;
        private set
        {
            if (!Set(ref _rightsAudit, value)) return;
            OnPropertyChanged(nameof(RightsAuditSummaryText));
            OnPropertyChanged(nameof(FilteredRightsAuditEntries));
        }
    }
    public IReadOnlyList<AuditFilterOption> RightsAuditFilters =>
    [
        new("all", T("project.filterAll")),
        new("needsReview", T("project.needsReview")),
        new("attributionRequired", T("license.attribution")),
        new("publicDomain", T("license.publicDomain")),
        new("rightsUnknown", T("project.rightsUnknown"))
    ];
    public string SelectedRightsAuditFilter
    {
        get => _selectedRightsAuditFilter;
        set
        {
            if (Set(ref _selectedRightsAuditFilter, value)) OnPropertyChanged(nameof(FilteredRightsAuditEntries));
        }
    }
    public IReadOnlyList<RightsAuditEntry> FilteredRightsAuditEntries => RightsAudit?.Entries.Where(entry => SelectedRightsAuditFilter switch
    {
        "needsReview" => entry.NeedsReview,
        "attributionRequired" => entry.AttributionRequired,
        "publicDomain" => entry.PublicDomain,
        "rightsUnknown" => !entry.RightsKnown,
        _ => true
    }).ToArray() ?? [];
    public string ProjectActionStatus { get => _projectActionStatus; private set => Set(ref _projectActionStatus, value); }
    public bool IsProjectWorking
    {
        get => _isProjectWorking;
        private set
        {
            if (!Set(ref _isProjectWorking, value)) return;
            (RefreshRightsAuditCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
            (FindDuplicatesCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
        }
    }
    public string RightsAuditSummaryText => RightsAudit is null ? "" :
        $"{T("project.totalAssets")}: {RightsAudit.Summary.TotalAssets} · {T("project.rightsUnknown")}: {RightsAudit.Summary.RightsUnknown} · {T("license.attribution")}: {RightsAudit.Summary.AttributionRequired}";
    public string LinkInput
    {
        get => _linkInput;
        set
        {
            if (!Set(ref _linkInput, value)) return;
            OnPropertyChanged(nameof(LinkDetectedText));
            OnPropertyChanged(nameof(LinkAnalyzeText));
        }
    }
    public string LinkStatus { get => _linkStatus; set => Set(ref _linkStatus, value); }
    public bool IsLinkAnalyzing
    {
        get => _isLinkAnalyzing;
        private set
        {
            if (!Set(ref _isLinkAnalyzing, value)) return;
            (AnalyzeLinksCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
        }
    }
    public string DownloadRoot => _settings.Current.DownloadRoot;
    public string LanguageCode => _localization.Language;
    public string LanguageButton => $"🌐 {_localization.DisplayName}";
    public string CurrentVersion
    {
        get
        {
            var version = typeof(MainViewModel).Assembly.GetName().Version;
            return version is null ? "0.13.0" : $"{version.Major}.{version.Minor}.{Math.Max(0, version.Build)}";
        }
    }
    public bool IsUpdateChecking
    {
        get => _isUpdateChecking;
        private set
        {
            if (!Set(ref _isUpdateChecking, value)) return;
            (CheckForUpdatesCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
        }
    }
    public string UpdateStatus => _updateStatusCode switch
    {
        "checking" => T("update.checking"),
        "upToDate" => T("update.upToDate"),
        "noNetwork" => T("update.noNetwork"),
        "timeout" => T("update.timeout"),
        "rateLimited" => T("update.rateLimited"),
        "failed" => T("update.checkFailed"),
        _ => ""
    };

    public string T(string key) => _localization.Text(key);
    public string NavSearch => T("nav.quickSearch");
    public string NavWorkspace => T("nav.workspace");
    public string NavScript => T("nav.scriptSearch");
    public string NavLinkDownloader => T("nav.linkDownloader");
    public string NavProjects => T("nav.projects");
    public string NavFavorites => T("nav.favorites");
    public string NavDownloads => T("nav.downloads");
    public string NavHistory => T("search.history");
    public string NavSettings => T("nav.settings");
    public string NavFeedback => T("nav.feedback");
    public string AccessibilityNavigationText => T("accessibility.navigation");
    public string AccessibilityLinkInputText => T("accessibility.linkInput");
    public string AccessibilitySearchResultsText =>
        _localization.Text("accessibility.searchResults", ResultsView.Cast<object>().Count());
    public string SearchTagline => T("search.tagline");
    public string SearchPlaceholder => T("search.placeholder");
    public string SearchApiRecommendation => T("search.apiRecommendation");
    public string SearchButtonText => T("search.button");
    public string LoadMoreText => T("search.loadMore");
    public string LoadingMoreText => T("search.loadingMore");
    public string StopText => T("common.stop");
    public string KeywordsTitle => T("search.currentKeywords");
    public string SmartExpansionText => T("search.smartExpansion");
    public string AddKeywordText => T("search.addKeyword");
    public string RegenerateKeywordsText => T("search.regenerateKeywords");
    public string SearchLanguagesToggleText =>
        T(ShowAllSearchLanguages ? "search.hideAllLanguages" : "search.showAllLanguages");
    public string TypeTitle => T("filter.type");
    public string OrientationTitle => T("filter.orientation");
    public string ResolutionTitle => T("filter.resolution");
    public string DurationTitle => T("filter.duration");
    public string LicenseTitle => T("filter.license");
    public string SortTitle => T("filter.sort");
    public string RelevanceModeTitle => T("search.relevance.mode");
    public string ClearFiltersText => T("filter.clear");
    public string RelevancePreciseText => T("search.relevance.precise");
    public string RelevanceBalancedText => T("search.relevance.balanced");
    public string RelevanceBroadText => T("search.relevance.broad");
    public string ProjectTitle => T("common.project");
    public string ProjectAllText => T("project.all");
    public string UncategorizedText => T("common.uncategorized");
    public string ScriptTitle => T("script.title");
    public string ScriptHelp => T("script.help");
    public string ScriptAnalyze => T("script.analyze");
    public string ProjectsTitle => T("project.title");
    public string NewProjectTitle => T("project.new");
    public string ProjectActionsTitle => T("project.actions");
    public string ExportProjectText => T("project.export");
    public string AttributionReportText => T("project.attributionReport");
    public string GenerateCreditsText => T("project.generateCredits");
    public string RightsAuditText => T("project.rightsAudit");
    public string RightsAuditDisclaimerText => T("project.rightsAuditDisclaimer");
    public string MissingLocalMediaText => T("project.missingLocalMedia");
    public string ProjectBackupText => T("project.backup");
    public string ImportProjectText => T("project.import");
    public string FindDuplicatesText => T("project.findDuplicates");
    public string ContactSheetText => T("project.contactSheet");
    public string ResetDuplicateDecisionsText => T("project.resetDuplicateDecisions");
    public string MarkReviewedText => T("project.markReviewed");
    public string KeepBothText => T("project.keepBoth");
    public string NotDuplicateText => T("project.notDuplicate");
    public string NeedsReviewText => T("project.needsReview");
    public string OpenOriginalText => T("project.openOriginal");
    public string RevealFileText => T("project.revealFile");
    public string RemoveFromProjectText => T("project.removeFromProject");
    public string FavoritesTitle => T("nav.favorites");
    public string DownloadsTitle => T("download.title");
    public string HistoryTitle => T("search.history");
    public string SettingsTitle => T("nav.settings");
    public string WorkspaceTitle => T("nav.workspace");
    public string WorkspaceTagline => T("workspace.tagline");
    public string WorkspaceGlobalSearchText => T("workspace.globalSearch");
    public string WorkspaceCommandPaletteText => T("workspace.commandPalette");
    public string WorkspaceSavedSearchesText => T("workspace.savedSearches");
    public string WorkspaceSmartCollectionsText => T("workspace.smartCollections");
    public string WorkspaceProviderHealthText => T("workspace.providerHealth");
    public string WorkspaceShortcutsText => T("workspace.shortcuts");
    public string ProjectDashboardText => T("workspace.projectDashboard");
    public string WorkspaceSearchPlaceholder => T("workspace.globalSearchPlaceholder");
    public string WorkspaceCommandPlaceholder => T("workspace.commandPalettePlaceholder");
    public string WorkspaceRunText => T("workspace.run");
    public string WorkspaceTestText => T("workspace.test");
    public string WorkspaceTestAllText => T("workspace.testAll");
    public string WorkspaceSaveSearchText => T("workspace.saveSearch");
    public string WorkspaceRenameText => T("workspace.rename");
    public string WorkspaceDuplicateText => T("workspace.duplicate");
    public string SourcesTitle => T("settings.sourcesProviders");
    public string ResearchSourcesTitle => $"{SearchScopeResearchText} {T("filter.source")}";
    public string ApiExplanation => T("settings.optionalAPIExplanation");
    public string PrivacyTitle => T("settings.privacy");
    public string PrivacyBody => T("settings.privacyBody");
    public string PreviewText => T("media.preview");
    public string ThumbnailUnavailableText => T("media.thumbnailUnavailable");
    public string RetryThumbnailText => T("media.retryThumbnail");
    public string FavoriteText => T("media.favorite");
    public string DownloadText => T("media.download");
    public string EditingCompatibleOutputText => T("link.output.editingCompatibleMP4");
    public string AudioOnlyOutputText => T("link.output.audioOnly");
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
    public string CloseText => T("common.close");
    public string CancelText => T("common.cancel");
    public string RetryText => T("common.retry");
    public string RetryFailedText => T("download.retryFailed");
    public string OpenFolderText => T("download.openFolder");
    public string OpenFileText => T("download.openFile");
    public string ClearHistoryText => T("history.clear");
    public string SearchAgainText => T("history.research");
    public string SaveText => T("common.save");
    public string RemoveKeyText => T("settings.removeAPIKey");
    public string ApiKeyText => T("settings.apiKey");
    public string TestConnectionText => T("settings.testConnection");
    public string DownloadFolderText => T("settings.downloadRoot");
    public string ChooseText => T("settings.choose");
    public string DownloadableOnlyText => T("filter.downloadableOnly");
    public string SearchScopeTitle => T("search.scope");
    public string SearchScopeMediaText => T("search.scope.media");
    public string SearchScopeResearchText => T("search.scope.research");
    public string SearchScopeAllText => T("search.scope.all");
    public string ResearchNotesText => T("research.notes");
    public string ResearchAddToNotesText => T("research.addToNotes");
    public string ResearchCopyCitationText => T("research.copyCitation");
    public string ResearchFindRelatedText => T("research.findRelatedMedia");
    public string ResearchAddAsMediaText => T("research.addAsMedia");
    public string ResearchSaveNoteText => T("common.save");
    public string ResearchRefreshMetadataText => T("research.refreshMetadata");
    public string ResearchTagsText => T("research.tags");
    public IReadOnlyList<ResearchReferenceRecord> CurrentResearchReferences =>
        CurrentProject is null ? [] : ResearchReferences.Where(value => value.ProjectID == CurrentProject.Id)
            .OrderByDescending(value => value.AddedAt).ToArray();
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
    public string LinkTagline => T("link.tagline");
    public string LinkPasteText => T("link.paste");
    public string LinkAnalyzeText => LinkURLLines().Count > 1 ? T("link.analyzeAll") : T("link.analyze");
    public string LinkDownloadSelectedText => T("link.downloadSelected");
    public string LinkDetectedText => _localization.Text("link.detectedCount", LinkURLLines().Count);
    public string LinkQualityText => T("link.quality");
    public string LinkSubtitlesText => T("link.subtitles");
    public string LinkOpenOriginalText => T("link.openOriginal");
    public string LinkLegalNotice => T("link.legalNotice");
    public string LinkFormatsText => T("link.formatsCount");
    public string LinkDownloadModeText => T("link.downloadMode");
    public string LinkOutputFormatText => T("link.outputFormat");
    public string LinkClipStartText => T("link.clip.start");
    public string LinkClipEndText => T("link.clip.end");
    public string ResetText => T("common.reset");
    public string ClipboardSettingText => T("clipboard.setting");
    public string ClipboardPrivacyDetail => T("clipboard.privacyDetail");
    public string ClipboardIgnoreText => T("clipboard.ignore");
    public string ClipboardDisableText => T("clipboard.disable");
    public string FeedbackIntro => T("feedback.intro");
    public string FeedbackReportBug => T("feedback.reportBug");
    public string FeedbackSuggestFeature => T("feedback.suggestFeature");
    public string FeedbackAskQuestion => T("feedback.askQuestion");
    public string FeedbackViewGitHub => T("feedback.viewGitHub");
    public string FeedbackViewReleases => T("feedback.viewReleases");
    public string FeedbackStarPrompt => T("feedback.starPrompt");
    public string FeedbackStarButton => $"⭐ {T("feedback.viewGitHub")}";
    public string FeedbackPrivacy => T("feedback.privacy");
    public string UpdateSettingsTitle => T("update.settingsTitle");
    public string UpdateSettingsDetail => T("update.settingsDetail");
    public string UpdateCurrentVersionLabel => T("update.currentVersion");
    public string UpdateCheckNowText => T("update.checkNow");

    public void SetLanguage(string language) => _localization.SetLanguage(language);

    public Task CheckForUpdatesOnLaunchAsync() =>
        _updateSession.TryBeginLaunchCheck() ? CheckForUpdatesAsync(manual: false) : Task.CompletedTask;

    public void NotNow() { }

    public void ViewUpdate(AppReleaseInfo release)
    {
        if (UpdateReleaseUrlValidator.IsTrusted(release.PageURL)) ShellService.OpenUrl(release.PageURL);
    }

    private async Task CheckForUpdatesAsync(bool manual)
    {
        if (IsUpdateChecking) return;
        IsUpdateChecking = true;
        if (manual) SetUpdateStatus("checking");
        try
        {
            var response = await _core.SendAsync(new CoreRequest
            {
                Action = "checkUpdate", Language = _settings.Current.Language
            }, timeout: TimeSpan.FromSeconds(20));
            if (!response.Success)
            {
                if (manual) SetUpdateStatus(response.ErrorCode switch
                {
                    "noNetwork" => "noNetwork", "timeout" => "timeout",
                    "rateLimited" => "rateLimited", _ => "failed"
                });
                return;
            }
            if (response.UpdateStatus == "available" && response.Release is { } release)
            {
                if (manual) SetUpdateStatus("");
                if (_updateSession.ShouldPresent(manual)) UpdateAvailable?.Invoke(release);
            }
            else if (manual) SetUpdateStatus("upToDate");
        }
        catch (CoreHostException error)
        {
            if (manual) SetUpdateStatus(error.Code == "timeout" ? "timeout" : "failed");
        }
        catch
        {
            if (manual) SetUpdateStatus("failed");
        }
        finally { IsUpdateChecking = false; }
    }

    private void SetUpdateStatus(string value)
    {
        _updateStatusCode = value;
        OnPropertyChanged(nameof(UpdateStatus));
    }

    public void CheckClipboardCandidate(string text)
    {
        if (!ClipboardDetectionEnabled || !IsLinkDownloaderPage || string.IsNullOrWhiteSpace(text)) return;
        var links = MediaLinkLines(text);
        if (links.Count == 0) return;
        var fresh = _clipboardSession.FreshCandidates(links, LinkURLLines());
        if (fresh.Count == 0) return;
        _clipboardSuggestion = string.Join(Environment.NewLine, fresh);
        OnPropertyChanged(nameof(HasClipboardSuggestion)); OnPropertyChanged(nameof(ClipboardSuggestionCount));
        OnPropertyChanged(nameof(ClipboardSuggestionText));
    }

    private async Task AnalyzeClipboardAsync()
    {
        if (!HasClipboardSuggestion) return;
        LinkInput = _clipboardSuggestion;
        _clipboardSuggestion = "";
        OnPropertyChanged(nameof(HasClipboardSuggestion));
        await AnalyzeLinksAsync();
    }

    private void IgnoreClipboard()
    {
        _clipboardSuggestion = "";
        OnPropertyChanged(nameof(HasClipboardSuggestion)); OnPropertyChanged(nameof(ClipboardSuggestionCount));
        OnPropertyChanged(nameof(ClipboardSuggestionText));
    }

    private static List<string> MediaLinkLines(string text)
    {
        string[] hosts = ["youtube.com", "youtu.be", "x.com", "twitter.com", "vimeo.com",
            "dailymotion.com", "tiktok.com", "twitch.tv", "reddit.com", "soundcloud.com",
            "facebook.com", "instagram.com"];
        string[] extensions = [".mp4", ".mov", ".m4v", ".webm", ".mp3", ".m4a", ".wav", ".ogg"];
        return text.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries).Select(value => value.Trim())
            .Where(value => LinkUrlSafety.TryCreate(value, out var uri) &&
                (hosts.Any(host => uri.Host.Equals(host, StringComparison.OrdinalIgnoreCase) ||
                    uri.Host.EndsWith("." + host, StringComparison.OrdinalIgnoreCase)) ||
                 extensions.Any(ext => uri.AbsolutePath.EndsWith(ext, StringComparison.OrdinalIgnoreCase))))
            .Distinct(StringComparer.OrdinalIgnoreCase).ToList();
    }

    public void OpenOfficialSearch(string provider)
    {
        var query = Uri.EscapeDataString(string.IsNullOrWhiteSpace(Query) ? "history" : Query.Trim());
        var url = provider switch
        {
            "nasa" => $"https://images.nasa.gov/search?q={query}",
            "libraryOfCongress" => $"https://www.loc.gov/film-and-videos/?q={query}",
            "nationalArchives" => $"https://catalog.archives.gov/search?q={query}",
            "europeana" => $"https://www.europeana.eu/en/search?query={query}",
            "peertube" => $"https://sepiasearch.org/search?search={query}",
            "videvo" => $"https://www.videvo.net/stock-video-footage/{query}/",
            "videezy" => $"https://www.videezy.com/free-video/{query}",
            "mixkit" => $"https://mixkit.co/free-stock-video/?q={query}",
            "coverr" => $"https://coverr.co/stock-video-footage?query={query}",
            "vimeo" => $"https://vimeo.com/search?q={query}",
            "dailymotion" => $"https://www.dailymotion.com/search/{query}/videos",
            "dareful" => $"https://dareful.com/?s={query}",
            "mazwai" => "https://mazwai.com/",
            "dvids" => $"https://www.dvidshub.net/search/?q={query}",
            "britishPathe" => $"https://www.britishpathe.com/?s={query}",
            "esa" => $"https://www.esa.int/esearch?q={query}",
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
            if (provider is "nationalArchives" or "europeana" or "videvo" or "videezy" or "mixkit" or "coverr" or "vimeo" or "mazwai" or "dvids" or "britishPathe" &&
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
        if (SearchScope != "research") _lastRequestedMediaType = MediaType;
        _searchCancellation?.Cancel();
        _searchCancellation = new CancellationTokenSource();
        var cancellationToken = _searchCancellation.Token;
        IsSearching = true;
        Results.Clear(); _candidateResults.Clear(); ResearchResults.Clear(); SelectedCount = 0;
        _continuations.Clear();
        _researchContinuations.Clear();
        OnPropertyChanged(nameof(CanLoadMore));
        if (SearchScope == "research")
        {
            try { await SearchResearchAsync(clean, cancellationToken, recordHistory: true); }
            catch (OperationCanceledException) { SearchStatus = T("search.stopped"); }
            catch (Exception error) { SearchStatus = error.Message; }
            finally { IsSearching = false; }
            return;
        }
        var selected = Providers.Where(x => x.Enabled).ToList();
        if (selected.Count == 0)
        {
            if (SearchScope == "all")
            {
                try { await SearchResearchAsync(clean, cancellationToken, recordHistory: true); }
                catch (OperationCanceledException) { SearchStatus = T("search.stopped"); }
                catch (Exception error) { SearchStatus = error.Message; }
            }
            else SearchStatus = T("search.noResults");
            IsSearching = false;
            return;
        }
        SearchStatus = T("search.searchingOthers");
        try
        {
            if (!string.Equals(_keywordSourceQuery, clean, StringComparison.Ordinal) || SearchKeywords.Count == 0)
                await RegenerateKeywordsAsync(cancellationToken);
            var effectiveKeywords = SearchKeywords.Where(x => x.IsEnabled && !string.IsNullOrWhiteSpace(x.Text))
                .Take(14).ToArray();
            if (effectiveKeywords.Length == 0)
                effectiveKeywords = [new SearchKeyword
                    { Id = Guid.NewGuid(), Text = clean, IsEnabled = true, Origin = "input",
                      Language = _settings.Current.Language, Priority = 0 }];
            _lastSearchQueries = effectiveKeywords.Select(x => x.Text.Trim()).ToArray();
            _lastEffectiveQuery = _lastSearchQueries[0];
            var researchTask = SearchScope == "all"
                ? SearchResearchAsync(clean, cancellationToken, recordHistory: false)
                : Task.CompletedTask;
            var tasks = selected.ToDictionary(option => option.Id,
                option => SearchProviderExpandedAsync(option, effectiveKeywords, cancellationToken));
            var pending = tasks.Values.ToList();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            while (pending.Count > 0)
            {
                var completed = await Task.WhenAny(pending);
                pending.Remove(completed);
                var batch = await completed;
                if (batch.Continuation is not null) _continuations[batch.Provider] = batch.Continuation;
                else _continuations.Remove(batch.Provider);
                foreach (var asset in batch.Assets)
                    if (seen.Add(asset.StableId))
                        _candidateResults.Add(asset);
                await ApplyRankedCandidatesAsync(clean, cancellationToken);
                SearchStatus = pending.Count > 0
                    ? $"{T("search.searchingOthers")}  {Results.Count}"
                    : _localization.Text("search.found", Results.Count);
                OnPropertyChanged(nameof(CanLoadMore));
                (LoadMoreCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
            }
            await _core.SendAsync(new CoreRequest
            {
                Action = "addHistory", Query = clean, Keywords = SearchKeywords.Select(x => x.Text).ToArray(),
                KeywordDetails = SearchKeywords.Where(x => x.IsEnabled).ToArray(),
                ProviderIDs = selected.Select(x => x.Id).ToArray(), ProjectID = CurrentProject?.Id.ToString(),
                ResultCount = Results.Count, Language = _settings.Current.Language
            }, cancellationToken: cancellationToken);
            await researchTask;
            await LoadDatabaseAsync();
        }
        catch (OperationCanceledException) { SearchStatus = T("search.stopped"); }
        catch (Exception error) { SearchStatus = error.Message; }
        finally
        {
            IsSearching = false;
            if (_refreshMediaTypeAfterSearch)
            {
                _refreshMediaTypeAfterSearch = false;
                _ = SearchAsync();
            }
        }
    }

    private async Task SearchResearchAsync(string query, CancellationToken cancellationToken, bool recordHistory)
    {
        var selected = ResearchProviders.Where(provider => provider.Enabled).Select(provider => provider.Id).ToArray();
        if (selected.Length == 0)
        {
            ResearchResults.Clear();
            _researchContinuations.Clear();
            SearchStatus = T("search.noResults");
            OnPropertyChanged(nameof(CanLoadMore));
            return;
        }
        SearchStatus = T("search.searchingOthers");
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "researchSearch", Query = query, Language = _settings.Current.Language,
            PageSize = 12, ProviderIDs = selected
        }, cancellationToken: cancellationToken);
        var records = (response.ResearchBatches ?? [])
            .SelectMany(batch => batch.Records)
            .GroupBy(record => $"{record.Provider}:{record.SourceNativeID ?? record.CanonicalURL}", StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First()).ToArray();
        _researchContinuations.Clear();
        foreach (var batch in response.ResearchBatches ?? [])
            if (batch.Continuation is not null) _researchContinuations[batch.Provider] = batch.Continuation;
        _lastResearchQuery = query;
        OnPropertyChanged(nameof(CanLoadMore));
        var ranked = await _core.SendAsync(new CoreRequest
        {
            Action = "rankResearch", Query = query, ResearchRecords = records,
            Keywords = SearchKeywords.Where(keyword => keyword.IsEnabled).Select(keyword => keyword.Text).ToArray(),
            RelevanceMode = RelevanceMode, Language = _settings.Current.Language
        }, cancellationToken: cancellationToken);
        ResearchResults.Clear();
        foreach (var record in ranked.ResearchRecords ?? records) ResearchResults.Add(record);
        SearchStatus = _localization.Text("research.found", ResearchResults.Count);
        if (recordHistory)
        {
            await _core.SendAsync(new CoreRequest
            {
                Action = "addHistory", Query = query, Keywords = SearchKeywords.Select(keyword => keyword.Text).ToArray(),
                KeywordDetails = SearchKeywords.Where(keyword => keyword.IsEnabled).ToArray(),
                ProviderIDs = [], ProjectID = CurrentProject?.Id.ToString(), ResultCount = ResearchResults.Count,
                Language = _settings.Current.Language
            }, cancellationToken: cancellationToken);
            await LoadDatabaseAsync();
        }
    }

    private async Task RegenerateKeywordsAsync(CancellationToken cancellationToken = default)
    {
        var clean = Query.Trim();
        if (clean.Length == 0) return;
        var keywords = await _core.SendAsync(new CoreRequest
        {
            Action = "keywords", Query = clean, SmartExpansion = SmartExpansionEnabled,
            Language = _settings.Current.Language
        }, cancellationToken: cancellationToken);
        SearchKeywords.Clear();
        foreach (var keyword in keywords.Keywords ?? []) SearchKeywords.Add(keyword);
        SearchKeywordsView.Refresh();
        _keywordSourceQuery = clean;
    }

    private async Task<ProviderBatch> SearchProviderExpandedAsync(
        ProviderOption option, IReadOnlyList<SearchKeyword> queries, CancellationToken cancellationToken)
    {
        var limited = option.Id is ("nationalArchives" or "europeana" or "videvo" or "videezy"
            or "mixkit" or "coverr" or "vimeo" or "mazwai" or "dvids" or "britishPathe") && string.IsNullOrWhiteSpace(ReadCredential(option.Id));
        var selectedQueries = queries.Take(limited ? 1 : 14)
            .DistinctBy(keyword => keyword.Text.Trim(), StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var assets = new List<MediaAsset>();
        ProviderBatch? primary = null;
        ProviderBatch? successful = null;
        var directOrTool = option.Id is ("pexels" or "pixabay" or "youtube" or "dareful" or "esa")
            && string.IsNullOrWhiteSpace(ReadCredential(option.Id));
        var perProviderLimit = directOrTool ? 1 : 2;
        async Task<(int Index, ProviderBatch Batch)> RunQueryAsync(int index)
        {
            var keyword = selectedQueries[index];
            await SearchNetworkLimit.WaitAsync(cancellationToken);
            try
            {
                var batch = await SearchProviderAsync(option, keyword.Text.Trim(), cancellationToken);
                foreach (var asset in batch.Assets)
                {
                    asset.OriginalMetadata["matchedQuery"] = keyword.Text.Trim();
                    if (!string.IsNullOrWhiteSpace(keyword.Language))
                        asset.OriginalMetadata["matchedQueryLanguage"] = keyword.Language;
                    if (!string.IsNullOrWhiteSpace(keyword.Origin))
                        asset.OriginalMetadata["matchedQueryOrigin"] = keyword.Origin;
                    asset.OriginalMetadata["matchedQueryPriority"] = (keyword.Priority ?? index).ToString();
                }
                return (Index: index, Batch: batch);
            }
            finally { SearchNetworkLimit.Release(); }
        }
        var nextIndex = 0;
        var tasks = new List<Task<(int Index, ProviderBatch Batch)>>();
        while (nextIndex < Math.Min(perProviderLimit, selectedQueries.Length))
            tasks.Add(RunQueryAsync(nextIndex++));
        var halted = false;
        while (tasks.Count > 0)
        {
            var completed = await Task.WhenAny(tasks);
            tasks.Remove(completed);
            var result = await completed;
            if (result.Index == 0 || primary is null) primary = result.Batch;
            if (result.Batch.Assets.Count > 0) successful ??= result.Batch;
            assets.AddRange(result.Batch.Assets);
            if (result.Batch.State.Availability is "rateLimited" or "temporarilyBlocked" or
                "authenticationRequired") halted = true;
            if (!halted && nextIndex < selectedQueries.Length)
                tasks.Add(RunQueryAsync(nextIndex++));
        }
        var first = successful ?? primary ?? new ProviderBatch
        {
            Provider = option.Id, DisplayName = option.DisplayName,
            State = new ProviderState { Availability = "unavailable" }
        };
        return new ProviderBatch
        {
            Provider = first.Provider, DisplayName = first.DisplayName, Mode = first.Mode,
            State = first.State, Continuation = first.Continuation, TotalResults = first.TotalResults,
            ErrorCode = first.ErrorCode,
            Assets = assets.GroupBy(value => value.StableId, StringComparer.OrdinalIgnoreCase)
                .Select(group => group.First()).ToArray()
        };
    }

    private async Task<ProviderBatch> SearchProviderAsync(
        ProviderOption option,
        string query,
        CancellationToken cancellationToken,
        ProviderContinuation? continuation = null)
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
                Continuation = continuation,
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

    private async Task LoadMoreAsync()
    {
        if (SearchScope == "research" || (_continuations.Count == 0 && _researchContinuations.Count > 0))
        {
            await LoadMoreResearchAsync();
            return;
        }
        if (_continuations.Count == 0 || string.IsNullOrWhiteSpace(_lastEffectiveQuery)) return;
        IsLoadingMore = true;
        var cancellationToken = _searchCancellation?.Token ?? CancellationToken.None;
        var targets = Providers.Where(option => option.Enabled && _continuations.ContainsKey(option.Id)).ToList();
        var tasks = targets.Select(async option =>
        {
            var continuation = _continuations[option.Id];
            var batch = await SearchProviderAsync(option, _lastEffectiveQuery, cancellationToken, continuation);
            return (Batch: batch, Previous: continuation);
        }).ToList();
        var seen = _candidateResults.Select(asset => asset.StableId)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        try
        {
            while (tasks.Count > 0)
            {
                var completed = await Task.WhenAny(tasks);
                tasks.Remove(completed);
                var result = await completed;
                var batch = result.Batch;
                if (batch.State.Availability == "unavailable")
                    _continuations[batch.Provider] = result.Previous;
                else if (batch.Continuation is not null) _continuations[batch.Provider] = batch.Continuation;
                else _continuations.Remove(batch.Provider);
                foreach (var asset in batch.Assets)
                    if (seen.Add(asset.StableId))
                        _candidateResults.Add(asset);
                await ApplyRankedCandidatesAsync(Query.Trim(), cancellationToken);
                SearchStatus = _localization.Text("search.found", Results.Count);
            }
        }
        catch (OperationCanceledException) { SearchStatus = T("search.stopped"); }
        finally
        {
            IsLoadingMore = false;
            OnPropertyChanged(nameof(CanLoadMore));
            (LoadMoreCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
        }
    }

    private async Task LoadMoreResearchAsync()
    {
        if (_researchContinuations.Count == 0 || string.IsNullOrWhiteSpace(_lastResearchQuery)) return;
        IsLoadingMore = true;
        var cancellationToken = _searchCancellation?.Token ?? CancellationToken.None;
        try
        {
            var targets = _researchContinuations.ToArray();
            foreach (var target in targets)
            {
                var response = await _core.SendAsync(new CoreRequest
                {
                    Action = "researchSearch", Query = _lastResearchQuery, Language = _settings.Current.Language,
                    PageSize = 12, ProviderIDs = [target.Key], Continuation = target.Value
                }, cancellationToken: cancellationToken);
                var batch = response.ResearchBatches?.FirstOrDefault();
                if (batch is null || !string.IsNullOrWhiteSpace(batch.ErrorCode)) continue;
                if (batch.Continuation is null) _researchContinuations.Remove(target.Key);
                else _researchContinuations[target.Key] = batch.Continuation;
                var known = ResearchResults.Select(record => $"{record.Provider}:{record.SourceNativeID ?? record.CanonicalURL}")
                    .ToHashSet(StringComparer.OrdinalIgnoreCase);
                foreach (var record in batch.Records)
                    if (known.Add($"{record.Provider}:{record.SourceNativeID ?? record.CanonicalURL}")) ResearchResults.Add(record);
            }
            var ranked = await _core.SendAsync(new CoreRequest
            {
                Action = "rankResearch", Query = _lastResearchQuery,
                ResearchRecords = ResearchResults.ToArray(), Keywords = SearchKeywords.Where(value => value.IsEnabled).Select(value => value.Text).ToArray(),
                RelevanceMode = RelevanceMode, Language = _settings.Current.Language
            }, cancellationToken: cancellationToken);
            if (ranked.ResearchRecords is not null)
            {
                ResearchResults.Clear();
                foreach (var record in ranked.ResearchRecords) ResearchResults.Add(record);
            }
            SearchStatus = _localization.Text("research.found", ResearchResults.Count);
        }
        catch (OperationCanceledException) { SearchStatus = T("search.stopped"); }
        finally
        {
            IsLoadingMore = false;
            OnPropertyChanged(nameof(CanLoadMore));
            (LoadMoreCommand as AsyncRelayCommand)?.RaiseCanExecuteChanged();
        }
    }

    private async Task RerankCurrentAsync()
    {
        var query = Query.Trim();
        if (query.Length == 0 || _candidateResults.Count == 0) return;
        try { await ApplyRankedCandidatesAsync(query, CancellationToken.None); }
        catch { }
    }

    private async Task ApplyRankedCandidatesAsync(string query, CancellationToken cancellationToken)
    {
        if (query.Length == 0) return;
        var selected = Results.Where(asset => asset.IsSelected).Select(asset => asset.StableId)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "rankAssets", Query = query, Assets = _candidateResults.ToArray(),
            RelevanceMode = RelevanceMode, Keywords = _lastSearchQueries,
            KeywordDetails = SearchKeywords.Where(x => x.IsEnabled).ToArray(),
            Language = _settings.Current.Language
        }, cancellationToken: cancellationToken);
        Results.Clear();
        foreach (var asset in response.Assets ?? [])
        {
            asset.IsSelected = selected.Contains(asset.StableId);
            asset.PropertyChanged += ResultPropertyChanged;
            Results.Add(asset);
        }
        SelectedCount = Results.Count(asset => asset.IsSelected);
        ResultsView.Refresh();
        ScheduleDuplicateReview();
    }

    private void ScheduleDuplicateReview()
    {
        _duplicateCancellation?.Cancel();
        _duplicateCancellation?.Dispose();
        var cancellation = new CancellationTokenSource();
        _duplicateCancellation = cancellation;
        SearchDuplicateItems.Clear();
        SearchDuplicateSummary = "";
        OnPropertyChanged(nameof(HasDuplicateGroups));
        OnPropertyChanged(nameof(HasGroupedDuplicateView));
        if (!DetectSearchDuplicates) return;
        var snapshot = ResultsView.Cast<MediaAsset>().ToArray();
        if (snapshot.Length < 2) return;
        _ = AnalyzeSearchDuplicatesAsync(snapshot, cancellation);
    }

    private async Task AnalyzeSearchDuplicatesAsync(
        MediaAsset[] snapshot, CancellationTokenSource cancellation)
    {
        var metadataApplied = false;
        try
        {
            // Render the ungrouped results first; never hold up search or filtering.
            await Task.Delay(120, cancellation.Token);
            var response = await _core.SendAsync(new CoreRequest
            {
                Action = "analyzeSearchDuplicates", Assets = snapshot,
                Language = _settings.Current.Language
            }, cancellationToken: cancellation.Token);
            if (cancellation.IsCancellationRequested || response.SearchDuplicateReview is not { } review)
                return;
            ApplySearchDuplicateReview(snapshot, review);
            metadataApplied = true;
            if (review.ThumbnailCandidateIDs.Count == 0) return;
            var hashes = await DuplicateThumbnailHashService.Shared.HashesAsync(
                snapshot, review.ThumbnailCandidateIDs, cancellation.Token);
            if (cancellation.IsCancellationRequested || hashes.Count == 0) return;
            var visualResponse = await _core.SendAsync(new CoreRequest
            {
                Action = "analyzeSearchDuplicates", Assets = snapshot,
                ThumbnailHashes = hashes, Language = _settings.Current.Language
            }, cancellationToken: cancellation.Token);
            if (!cancellation.IsCancellationRequested && visualResponse.SearchDuplicateReview is { } visualReview)
                ApplySearchDuplicateReview(snapshot, visualReview);
        }
        catch (OperationCanceledException) { }
        catch
        {
            // Review is optional. The original ResultsView stays available on any failure.
            if (!cancellation.IsCancellationRequested && !metadataApplied)
            {
                SearchDuplicateItems.Clear();
                SearchDuplicateSummary = "";
                OnPropertyChanged(nameof(HasDuplicateGroups));
                OnPropertyChanged(nameof(HasGroupedDuplicateView));
            }
        }
    }

    private void ApplySearchDuplicateReview(MediaAsset[] snapshot, SearchDuplicateReview review)
    {
        var expanded = SearchDuplicateItems.Where(item => item.IsGroup && item.Expanded)
            .Select(item => item.Id).ToHashSet(StringComparer.Ordinal);
        var byId = snapshot.ToDictionary(asset => asset.StableId, StringComparer.Ordinal);
        SearchDuplicateItems.Clear();
        foreach (var entry in review.Entries)
        {
            if (!byId.TryGetValue(entry.RecommendedID, out var recommended)) continue;
            var item = new SearchDuplicateDisplayItem { Id = entry.Id, Recommended = recommended,
                RecommendedLabel = T("duplicate.recommendedVersion"),
                Expanded = expanded.Contains(entry.Id) || !_settings.Current.CollapseDuplicateGroups };
            foreach (var id in entry.MemberIDs)
                if (id != entry.RecommendedID && byId.TryGetValue(id, out var other))
                    item.OtherVersions.Add(other);
            if (item.IsGroup)
            {
                var confidence = entry.Confidence switch
                {
                    "exact" => T("duplicate.exact"),
                    "likely" => T("duplicate.likely"),
                    _ => T("duplicate.possible")
                };
                item.Header = _localization.Text("duplicate.groupTitle", confidence, entry.MemberIDs.Count);
            }
            SearchDuplicateItems.Add(item);
        }
        SearchDuplicateSummary = HasDuplicateGroups
            ? _localization.Text("duplicate.summary", review.ResultCount,
                review.UniqueCount, review.Groups.Count)
            : "";
        OnPropertyChanged(nameof(HasDuplicateGroups));
        OnPropertyChanged(nameof(HasGroupedDuplicateView));
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

    private static MediaAsset? WithEditingOutput(MediaAsset? asset, string preset)
    {
        if (asset is null || asset.DownloadStrategy != "ytDLP") return asset;
        var metadata = new Dictionary<string, string>(asset.OriginalMetadata)
        {
            ["linkOutputPreset"] = preset,
            ["workflowVariantID"] = preset,
            ["linkMediaDuration"] = asset.Duration?.ToString(
                System.Globalization.CultureInfo.InvariantCulture) ?? "",
            ["linkAudioOnly"] = preset == "audioOnly" ? "true" : "false"
        };
        if (preset == "audioOnly")
            metadata["linkFormatSelector"] = "bestaudio[acodec!=none]/best";
        return asset.CloneForWorkflow(
            $"{asset.Id}:{preset}", metadata,
            preset == "audioOnly" ? "audio" : asset.MediaType,
            preset == "audioOnly" ? "m4a" :
                preset == "editingCompatibleMP4" ? "mp4" : asset.FileType);
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

    private async Task RefreshRightsAuditAsync()
    {
        if (CurrentProject is null || IsProjectWorking) return;
        IsProjectWorking = true;
        ProjectActionStatus = T("project.auditLoading");
        try
        {
            var response = await _core.SendAsync(new CoreRequest
            {
                Action = "projectRightsAudit", ProjectID = CurrentProject.Id.ToString(),
                Language = _settings.Current.Language
            }, timeout: TimeSpan.FromSeconds(45));
            if (!response.Success) throw new CoreHostException(response.ErrorCode ?? "projectAuditFailed", response.ErrorMessage ?? T("project.actionFailed"));
            RightsAudit = response.RightsAudit;
            OnPropertyChanged(nameof(FilteredRightsAuditEntries));
            ProjectActionStatus = "";
        }
        catch { ProjectActionStatus = T("project.actionFailed"); }
        finally { IsProjectWorking = false; }
    }

    private async Task FindDuplicatesAsync()
    {
        if (CurrentProject is null || IsProjectWorking) return;
        IsProjectWorking = true;
        ProjectActionStatus = T("project.scanningDuplicates");
        try
        {
            var response = await _core.SendAsync(new CoreRequest
            {
                Action = "findProjectDuplicates", ProjectID = CurrentProject.Id.ToString(),
                Language = _settings.Current.Language
            }, timeout: TimeSpan.FromMinutes(5));
            if (!response.Success) throw new CoreHostException(response.ErrorCode ?? "duplicateFailed", response.ErrorMessage ?? T("project.actionFailed"));
            Replace(DuplicateGroups, response.DuplicateGroups ?? []);
            ProjectActionStatus = DuplicateGroups.Count == 0 ? T("project.noDuplicates") : "";
        }
        catch { ProjectActionStatus = T("project.actionFailed"); }
        finally { IsProjectWorking = false; }
    }

    private async Task SetReviewedAsync(RightsAuditEntry? entry, bool reviewed)
    {
        if (CurrentProject is null || entry is null) return;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "setProjectReviewed", ProjectID = CurrentProject.Id.ToString(),
            StableAssetID = entry.Item.StableID, Reviewed = reviewed, Language = _settings.Current.Language
        });
        ApplyDatabase(response.Database);
        await RefreshRightsAuditAsync();
    }

    private async Task SetDuplicateDecisionAsync(DuplicateGroup? group, string decision)
    {
        if (CurrentProject is null || group is null) return;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "setDuplicateDecision", ProjectID = CurrentProject.Id.ToString(),
            PairKey = group.DecisionKey, DuplicateDecision = decision, Language = _settings.Current.Language
        });
        ApplyDatabase(response.Database);
        DuplicateGroups.Remove(group);
    }

    private async Task ResetDuplicateDecisionsAsync()
    {
        if (CurrentProject is null) return;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "resetDuplicateDecisions", ProjectID = CurrentProject.Id.ToString(),
            Language = _settings.Current.Language
        });
        ApplyDatabase(response.Database);
        await FindDuplicatesAsync();
    }

    public async Task<RightsAuditReport?> GetCurrentRightsAuditAsync()
    {
        if (CurrentProject is null) return null;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "projectRightsAudit", ProjectID = CurrentProject.Id.ToString(),
            Language = _settings.Current.Language
        }, timeout: TimeSpan.FromSeconds(45));
        if (!response.Success) throw new CoreHostException(response.ErrorCode ?? "projectAuditFailed", response.ErrorMessage ?? T("project.actionFailed"));
        RightsAudit = response.RightsAudit;
        OnPropertyChanged(nameof(FilteredRightsAuditEntries));
        return RightsAudit;
    }

    private async Task RemoveAssetFromProjectAsync(ProjectAssetItem? item)
    {
        if (CurrentProject is null || item is null) return;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "removeAssetFromProject", ProjectID = CurrentProject.Id.ToString(),
            StableAssetID = item.StableID, Language = _settings.Current.Language
        });
        if (!response.Success) throw new CoreHostException(response.ErrorCode ?? "projectRemovalFailed", response.ErrorMessage ?? T("project.actionFailed"));
        ApplyDatabase(response.Database);
        await RefreshRightsAuditAsync();
        await FindDuplicatesAsync();
    }

    public async Task<byte[]?> BuildProjectReportAsync(string format, string section, bool includeLocalPaths)
    {
        if (CurrentProject is null) return null;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "exportProjectReport", ProjectID = CurrentProject.Id.ToString(), ExportFormat = format,
            ExportSection = section, IncludeLocalFilePaths = includeLocalPaths, Language = _settings.Current.Language
        }, timeout: TimeSpan.FromSeconds(60));
        if (!response.Success || string.IsNullOrWhiteSpace(response.DataBase64))
            throw new CoreHostException(response.ErrorCode ?? "exportFailed", response.ErrorMessage ?? T("project.actionFailed"));
        return Convert.FromBase64String(response.DataBase64);
    }

    public async Task<string?> BuildProjectCreditsAsync(string style)
    {
        if (CurrentProject is null) return null;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "generateProjectCredits", ProjectID = CurrentProject.Id.ToString(), CreditsStyle = style,
            Language = _settings.Current.Language
        });
        if (!response.Success) throw new CoreHostException(response.ErrorCode ?? "creditsFailed", response.ErrorMessage ?? T("project.actionFailed"));
        return response.Text;
    }

    public async Task<byte[]?> BuildProjectBackupAsync()
    {
        if (CurrentProject is null) return null;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "exportProjectBackup", ProjectID = CurrentProject.Id.ToString(), Language = _settings.Current.Language
        }, timeout: TimeSpan.FromSeconds(60));
        if (!response.Success || string.IsNullOrWhiteSpace(response.DataBase64))
            throw new CoreHostException(response.ErrorCode ?? "backupFailed", response.ErrorMessage ?? T("project.actionFailed"));
        return Convert.FromBase64String(response.DataBase64);
    }

    public async Task<bool> ImportProjectBackupAsync(byte[] data)
    {
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "importProjectBackup", DataBase64 = Convert.ToBase64String(data), Language = _settings.Current.Language
        }, timeout: TimeSpan.FromSeconds(60));
        if (!response.Success) throw new CoreHostException(response.ErrorCode ?? "projectImportFailed", response.ErrorMessage ?? T("project.actionFailed"));
        ApplyDatabase(response.Database);
        CurrentProject = response.Project;
        return response.Project is not null;
    }

    public async Task<ContactSheetPlan?> BuildContactSheetPlanAsync(int columns, bool includeRights)
    {
        if (CurrentProject is null) return null;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "contactSheetPlan", ProjectID = CurrentProject.Id.ToString(), Columns = columns,
            IncludeRights = includeRights, Language = _settings.Current.Language
        }, timeout: TimeSpan.FromSeconds(60));
        if (!response.Success) throw new CoreHostException(response.ErrorCode ?? "contactSheetFailed", response.ErrorMessage ?? T("project.actionFailed"));
        return response.ContactSheetPlan;
    }

    private async Task SearchHistoryAsync(SearchHistoryRecord? history)
    {
        if (history is null) return;
        Query = history.OriginalQuery;
        SearchKeywords.Clear();
        var restored = history.KeywordDetails ?? history.Keywords.Select(text => new SearchKeyword
        {
            Id = Guid.NewGuid(), Text = text, IsEnabled = true,
            Language = _settings.Current.Language, Origin = "userAdded", Priority = 99
        }).ToArray();
        foreach (var keyword in restored) SearchKeywords.Add(keyword);
        SearchKeywordsView.Refresh();
        _keywordSourceQuery = history.OriginalQuery;
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

    private void RefreshWorkspaceCommands()
    {
        var query = CommandPaletteQuery.Trim();
        var values = new[]
        {
            new WorkspaceCommandItem { Id = "searchMedia", Title = T("workspace.command.searchMedia.title"), Detail = T("workspace.command.searchMedia.subtitle") },
            new WorkspaceCommandItem { Id = "searchResearch", Title = T("workspace.command.searchResearch.title"), Detail = T("workspace.command.searchResearch.subtitle") },
            new WorkspaceCommandItem { Id = "searchAll", Title = T("workspace.command.searchAll.title"), Detail = T("workspace.command.searchAll.subtitle") },
            new WorkspaceCommandItem { Id = "focusSearch", Title = T("workspace.command.focusSearch.title"), Detail = T("workspace.command.focusSearch.subtitle"), Shortcut = "Ctrl+F" },
            new WorkspaceCommandItem { Id = "clearSearch", Title = T("workspace.command.clearSearch.title"), Detail = T("workspace.command.clearSearch.subtitle") },
            new WorkspaceCommandItem { Id = "globalSearch", Title = T("workspace.command.globalSearch.title"), Detail = T("workspace.command.globalSearch.subtitle"), Shortcut = "Ctrl+Shift+G" },
            new WorkspaceCommandItem { Id = "newProject", Title = T("workspace.command.newProject.title"), Detail = T("workspace.command.newProject.subtitle"), Shortcut = "Ctrl+N" },
            new WorkspaceCommandItem { Id = "openProjects", Title = T("workspace.command.openProjects.title"), Detail = T("workspace.command.openProjects.subtitle"), Shortcut = "Ctrl+O" },
            new WorkspaceCommandItem { Id = "openResearchNotes", Title = T("workspace.command.openResearchNotes.title"), Detail = T("workspace.command.openResearchNotes.subtitle"), Shortcut = "Ctrl+Shift+R" },
            new WorkspaceCommandItem { Id = "openRightsAudit", Title = T("workspace.command.openRightsAudit.title"), Detail = T("workspace.command.openRightsAudit.subtitle") },
            new WorkspaceCommandItem { Id = "generateCredits", Title = T("workspace.command.generateCredits.title"), Detail = T("workspace.command.generateCredits.subtitle") },
            new WorkspaceCommandItem { Id = "exportProject", Title = T("workspace.command.exportProject.title"), Detail = T("workspace.command.exportProject.subtitle") },
            new WorkspaceCommandItem { Id = "findDuplicates", Title = T("workspace.command.findDuplicates.title"), Detail = T("workspace.command.findDuplicates.subtitle") },
            new WorkspaceCommandItem { Id = "generateContactSheet", Title = T("workspace.command.generateContactSheet.title"), Detail = T("workspace.command.generateContactSheet.subtitle") },
            new WorkspaceCommandItem { Id = "openFavorites", Title = T("workspace.command.openFavorites.title"), Detail = T("workspace.command.openFavorites.subtitle"), Shortcut = "Ctrl+Shift+F" },
            new WorkspaceCommandItem { Id = "openDownloads", Title = T("workspace.command.openDownloads.title"), Detail = T("workspace.command.openDownloads.subtitle"), Shortcut = "Ctrl+Shift+D" },
            new WorkspaceCommandItem { Id = "openHistory", Title = T("workspace.command.openHistory.title"), Detail = T("workspace.command.openHistory.subtitle") },
            new WorkspaceCommandItem { Id = "openSavedSearches", Title = T("workspace.command.openSavedSearches.title"), Detail = T("workspace.command.openSavedSearches.subtitle") },
            new WorkspaceCommandItem { Id = "openSmartCollections", Title = T("workspace.command.openSmartCollections.title"), Detail = T("workspace.command.openSmartCollections.subtitle") },
            new WorkspaceCommandItem { Id = "openProviderHealth", Title = T("workspace.command.openProviderHealth.title"), Detail = T("workspace.command.openProviderHealth.subtitle") },
            new WorkspaceCommandItem { Id = "openSettings", Title = T("workspace.command.openSettings.title"), Detail = T("workspace.command.openSettings.subtitle"), Shortcut = "Ctrl+," },
            new WorkspaceCommandItem { Id = "checkForUpdates", Title = T("workspace.command.checkForUpdates.title"), Detail = T("workspace.command.checkForUpdates.subtitle") },
            new WorkspaceCommandItem { Id = "retryFailedDownloads", Title = T("workspace.command.retryFailedDownloads.title"), Detail = T("workspace.command.retryFailedDownloads.subtitle") }
        };
        Replace(WorkspaceShortcutReference, values.Where(value => !string.IsNullOrWhiteSpace(value.Shortcut)));
        if (!string.IsNullOrWhiteSpace(query))
            values = values.Where(value => FuzzyMatches($"{value.Title} {value.Detail} {value.Id}", query)).ToArray();
        Replace(WorkspaceCommands, values);
    }

    private async Task ExecuteWorkspaceCommandAsync(string? command)
    {
        IsCommandPaletteOpen = false;
        switch (command)
        {
            case "searchMedia": SearchScope = "media"; CurrentPage = "search"; FocusSearchRequested?.Invoke(); break;
            case "searchResearch": SearchScope = "research"; CurrentPage = "search"; FocusSearchRequested?.Invoke(); break;
            case "searchAll": SearchScope = "all"; CurrentPage = "search"; FocusSearchRequested?.Invoke(); break;
            case "focusSearch": CurrentPage = "search"; FocusSearchRequested?.Invoke(); break;
            case "clearSearch": ClearCurrentSearch(); CurrentPage = "search"; FocusSearchRequested?.Invoke(); break;
            case "globalSearch": IsGlobalSearchOpen = true; break;
            case "newProject": CurrentPage = "projects"; NewProjectName = ""; break;
            case "openProjects": case "openResearchNotes": case "openRightsAudit": case "generateCredits":
            case "exportProject": case "findDuplicates": case "generateContactSheet":
                CurrentPage = "projects"; break;
            case "openFavorites": CurrentPage = "favorites"; break;
            case "openDownloads": CurrentPage = "downloads"; break;
            case "openHistory": CurrentPage = "history"; break;
            case "openSavedSearches": CurrentPage = "workspace"; break;
            case "openSmartCollections": CurrentPage = "workspace"; break;
            case "openProviderHealth": CurrentPage = "workspace"; break;
            case "openSettings": CurrentPage = "settings"; break;
            case "checkForUpdates": await CheckForUpdatesAsync(manual: true); break;
            case "retryFailedDownloads": Downloads.RetryFailed(); CurrentPage = "downloads"; break;
        }
    }

    private static bool FuzzyMatches(string value, string query)
    {
        var normalizedValue = value.Replace(" ", "", StringComparison.Ordinal).ToUpperInvariant();
        var normalizedQuery = query.Replace(" ", "", StringComparison.Ordinal).ToUpperInvariant();
        var cursor = 0;
        foreach (var character in normalizedQuery)
        {
            cursor = normalizedValue.IndexOf(character, cursor);
            if (cursor < 0) return false;
            cursor++;
        }
        return true;
    }

    private void ClearCurrentSearch()
    {
        _searchCancellation?.Cancel();
        Query = "";
        SearchKeywords.Clear();
        Results.Clear();
        ResearchResults.Clear();
        _candidateResults.Clear();
        _continuations.Clear();
        _researchContinuations.Clear();
        _lastRequestedMediaType = null;
        _refreshMediaTypeAfterSearch = false;
        SearchStatus = T("search.initialStatus");
    }

    // Keep the query and current result set intact. This is intentionally a
    // filter reset rather than a second form of “clear search”, so it is safe
    // to use from a keyboard workflow after a result set looks unexpectedly empty.
    private void ClearFilters()
    {
        var refreshMedia = _lastRequestedMediaType is not null &&
            _lastRequestedMediaType != "video" && SearchScope != "research";
        _suppressMediaTypeSearch = true;
        MediaType = "video";
        Orientation = "all";
        Resolution = "all";
        Duration = "all";
        LicenseFilter = "all";
        YearFrom = "";
        YearTo = "";
        DownloadableOnly = false;
        RelevanceMode = "balanced";
        Sort = "relevance";
        foreach (var provider in Providers) provider.Enabled = _settings.Current.EnabledProviders.Contains(provider.Id);
        foreach (var provider in ResearchProviders) provider.Enabled = true;
        _suppressMediaTypeSearch = false;
        ResultsView.Refresh();
        if (refreshMedia && !string.IsNullOrWhiteSpace(Query))
        {
            if (IsSearching)
            {
                _refreshMediaTypeAfterSearch = true;
                _searchCancellation?.Cancel();
            }
            else _ = SearchAsync();
        }
    }

    private async Task ScheduleWorkspaceSearchAsync()
    {
        _workspaceSearchCancellation?.Cancel();
        var cancellation = new CancellationTokenSource();
        _workspaceSearchCancellation = cancellation;
        try
        {
            await Task.Delay(180, cancellation.Token);
            await SearchWorkspaceAsync(cancellation.Token);
        }
        catch (OperationCanceledException) { }
    }

    private async Task SearchWorkspaceAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            WorkspaceStatus = T("search.searchingOthers");
            var response = await _core.SendAsync(new CoreRequest
            {
                Action = "workspaceSearch", Query = WorkspaceQuery, Language = _settings.Current.Language
            }, timeout: TimeSpan.FromSeconds(5), cancellationToken: cancellationToken);
            var entries = response.WorkspaceEntries ?? [];
            foreach (var entry in entries) entry.SectionTitle = T($"workspace.kind.{entry.Kind}");
            Replace(WorkspaceSearchResults, entries);
            WorkspaceSearchResultsView.Refresh();
            WorkspaceStatus = WorkspaceSearchResults.Count == 0 ? T("search.noResults") :
                _localization.Text("search.found", WorkspaceSearchResults.Count);
        }
        catch (OperationCanceledException) { }
        catch { WorkspaceStatus = T("workspace.searchUnavailable"); }
    }

    private async Task OpenWorkspaceResultAsync(WorkspaceSearchEntry? entry)
    {
        if (entry is null) return;
        IsGlobalSearchOpen = false;
        switch (entry.Kind)
        {
            case "project": case "researchReference": case "researchNote": CurrentPage = "projects"; break;
            case "favorite": case "media": CurrentPage = "favorites"; break;
            case "download": CurrentPage = "downloads"; break;
            case "localFile": if (!string.IsNullOrWhiteSpace(entry.LocalPath)) ShellService.Reveal(entry.LocalPath); break;
            case "searchHistory":
                Query = entry.Title;
                CurrentPage = "search";
                await RegenerateKeywordsAsync();
                break;
            case "savedSearch":
                if (Guid.TryParse(entry.Id.Replace("savedSearch:", "", StringComparison.Ordinal), out var savedID))
                    await RunSavedSearchAsync(SavedSearches.FirstOrDefault(value => value.Id == savedID));
                break;
        }
    }

    private async Task SaveCurrentSearchAsync()
    {
        var clean = Query.Trim();
        if (clean.Length == 0) return;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "addSavedSearch", Language = _settings.Current.Language,
            SavedSearch = new SavedSearchRecord
            {
                Id = Guid.NewGuid(), Name = clean, Query = clean, Keywords = SearchKeywords.ToArray(),
                SearchScope = SearchScope, MediaType = MediaType, Orientation = Orientation,
                Resolution = Resolution, Duration = Duration, LicenseFilter = LicenseFilter,
                YearFrom = int.TryParse(YearFrom, out var from) ? from : null,
                YearTo = int.TryParse(YearTo, out var to) ? to : null,
                DownloadableOnly = DownloadableOnly, RelevanceMode = RelevanceMode,
                ProviderIDs = Providers.Where(item => item.Enabled).Select(item => item.Id).ToArray(),
                CreatedAt = DateTimeOffset.UtcNow, UpdatedAt = DateTimeOffset.UtcNow
            }
        });
        ApplyDatabase(response.Database);
        CurrentPage = "workspace";
    }

    private async Task RunSavedSearchAsync(SavedSearchRecord? saved)
    {
        if (saved is null) return;
        _suppressMediaTypeSearch = true;
        Query = saved.Query;
        SearchScope = saved.SearchScope;
        MediaType = saved.MediaType; Orientation = saved.Orientation; Resolution = saved.Resolution;
        Duration = saved.Duration; LicenseFilter = saved.LicenseFilter;
        YearFrom = saved.YearFrom?.ToString() ?? ""; YearTo = saved.YearTo?.ToString() ?? "";
        DownloadableOnly = saved.DownloadableOnly; RelevanceMode = saved.RelevanceMode;
        foreach (var provider in Providers) provider.Enabled = saved.ProviderIDs.Contains(provider.Id);
        SearchKeywords.Clear();
        foreach (var keyword in saved.Keywords) SearchKeywords.Add(keyword);
        _keywordSourceQuery = Query;
        _suppressMediaTypeSearch = false;
        CurrentPage = "search";
        await SearchAsync();
    }

    private async Task RenameSavedSearchAsync(SavedSearchRecord? saved)
    {
        if (saved is null) return;
        var response = await _core.SendAsync(new CoreRequest
        { Action = "updateSavedSearch", SavedSearch = saved, Language = _settings.Current.Language });
        ApplyDatabase(response.Database);
    }

    private async Task DeleteSavedSearchAsync(SavedSearchRecord? saved)
    {
        if (saved is null) return;
        var response = await _core.SendAsync(new CoreRequest
        { Action = "deleteSavedSearch", SavedSearchID = saved.Id.ToString(), Language = _settings.Current.Language });
        ApplyDatabase(response.Database);
    }

    private async Task DuplicateSavedSearchAsync(SavedSearchRecord? saved)
    {
        if (saved is null) return;
        var response = await _core.SendAsync(new CoreRequest
        { Action = "duplicateSavedSearch", SavedSearchID = saved.Id.ToString(), Language = _settings.Current.Language });
        ApplyDatabase(response.Database);
    }

    private async Task TestWorkspaceProviderAsync(string? provider)
    {
        if (string.IsNullOrWhiteSpace(provider)) return;
        var status = await TestProviderAsync(provider);
        var state = status == T("settings.connectionSuccess") ? "healthy" :
            status.Contains("rate", StringComparison.OrdinalIgnoreCase) ? "rateLimited" : "degraded";
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "updateProviderHealth", Language = _settings.Current.Language,
            ProviderHealthRecord = new ProviderHealthRecord
            {
                ProviderID = provider, State = state, Message = status,
                TestedAt = DateTimeOffset.UtcNow
            }
        });
        ApplyDatabase(response.Database);
    }

    private async Task TestAllWorkspaceProvidersAsync()
    {
        // Two concurrent, user-triggered checks avoid treating this view as an
        // uptime monitor and keep provider quota usage intentionally modest.
        using var limiter = new SemaphoreSlim(2, 2);
        var tasks = Providers.Where(item => item.Enabled).Select(async item =>
        {
            await limiter.WaitAsync();
            try { await TestWorkspaceProviderAsync(item.Id); }
            finally { limiter.Release(); }
        }).ToArray();
        await Task.WhenAll(tasks);
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

    private async Task OpenFeedbackAsync(string? destination)
    {
        if (string.IsNullOrWhiteSpace(destination)) return;
        try
        {
            var response = await _core.SendAsync(new CoreRequest
            {
                Action = "feedbackURL", FeedbackDestination = destination,
                Language = _settings.Current.Language
            });
            ShellService.OpenUrl(response.Text);
        }
        catch { }
    }

    private async Task AnalyzeLinksAsync()
    {
        var lines = LinkInput.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
            .Select(value => value.Trim()).Where(value => value.Length > 0).Take(25).ToArray();
        LinkItems.Clear();
        foreach (var line in lines) LinkItems.Add(new LinkDownloadItem(line));
        if (lines.Length == 0) { LinkStatus = T("link.invalidURL"); return; }
        IsLinkAnalyzing = true;
        LinkStatus = T("link.analyzing");
        using var limit = new SemaphoreSlim(2, 2);
        try
        {
            var tasks = LinkItems.Select(async item =>
            {
                if (!LinkUrlSafety.TryCreate(item.RawURL, out _))
                {
                    item.ErrorMessage = T("link.unsupportedURL"); item.IsSelected = false; return;
                }
                await limit.WaitAsync();
                try
                {
                    item.Analysis = await _ytDlp.AnalyzeAsync(item.RawURL, CancellationToken.None);
                    item.SelectedQuality = item.AvailableQualities.FirstOrDefault() ?? "best";
                    item.SubtitleLanguage = item.SubtitleLanguages.FirstOrDefault() ?? "";
                    item.ConfigureQualityLabels(QualityLabel);
                    item.ConfigureCreatorLabels(
                        value => T($"link.scope.{value}"), value => T($"link.output.{value}"),
                        value => T($"link.clip.{value}"));
                    item.InitializeClipEnd();
                }
                catch (Exception error)
                {
                    item.ErrorMessage = LinkErrorMessage(error); item.IsSelected = false;
                }
                finally { limit.Release(); }
            }).ToArray();
            await Task.WhenAll(tasks);
            LinkStatus = LinkItems.Any(item => item.IsReady) ? T("link.analysisComplete") : T("link.noneAnalyzed");
        }
        finally { IsLinkAnalyzing = false; }
    }

    private void DownloadLinkSelected()
    {
        var selected = LinkItems.Where(item => item.IsSelected && item.IsReady).ToArray();
        foreach (var item in selected)
        {
            var analysis = item.Analysis!;
            var selector = item.SelectedQuality switch
            {
                "p1080" => "bestvideo[height<=1080]+bestaudio/best[height<=1080]",
                "p720" => "bestvideo[height<=720]+bestaudio/best[height<=720]",
                "p480" => "bestvideo[height<=480]+bestaudio/best[height<=480]",
                "audioOnly" => "bestaudio[acodec!=none]/best",
                _ => "bestvideo+bestaudio/best"
            };
            if (item.OutputPreset == "audioOnly") selector = "bestaudio[acodec!=none]/best";
            var metadata = new Dictionary<string, string>
            {
                ["sourceName"] = analysis.SourceName, ["linkDownloader"] = "true",
                ["linkFormatSelector"] = selector, ["linkQuality"] = item.SelectedQuality,
                ["linkDownloadSubtitles"] = item.DownloadSubtitles ? "true" : "false",
                ["linkSubtitleLanguages"] = item.SubtitleLanguage,
                ["linkAudioOnly"] = item.OutputPreset == "audioOnly" || item.SelectedQuality == "audioOnly" ? "true" : "false",
                ["linkOutputPreset"] = item.OutputPreset,
                ["linkMediaDuration"] = analysis.Duration?.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? ""
            };
            if (item.SelectedScope == "clip")
            {
                metadata["linkClipStart"] = item.ClipStartSeconds?.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? "";
                metadata["linkClipEnd"] = item.ClipEndSeconds?.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? "";
                metadata["linkClipDuration"] = item.ClipDuration?.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? "";
            }
            var audioOnly = item.OutputPreset == "audioOnly" || item.SelectedQuality == "audioOnly";
            var asset = new MediaAsset
            {
                Id = item.DownloadIdentity,
                Provider = "linkDownloader", Title = analysis.Title,
                ThumbnailURL = analysis.ThumbnailURL, SourcePageURL = analysis.OriginalURL,
                DownloadURL = analysis.OriginalURL, Creator = analysis.Creator,
                LicenseStatus = "UNKNOWN", Duration = analysis.Duration,
                Height = item.SelectedQuality switch { "p1080" => 1080, "p720" => 720, "p480" => 480, _ => null },
                FileType = audioOnly ? "m4a" : item.OutputPreset == "editingCompatibleMP4" ? "mp4" : "video",
                MediaType = audioOnly ? "audio" : "video",
                Downloadable = true, OriginalMetadata = metadata, SearchKeyword = analysis.OriginalURL,
                RelevanceScore = 1, DownloadStrategy = "ytDLP", DownloadAvailability = "conditional",
                RightsInfo = new RightsInfo { Source = analysis.SourceName, Known = false }
            };
            Downloads.Enqueue(asset, CurrentProject?.Id, CurrentProject?.Name ?? T("common.uncategorized"));
        }
        if (selected.Length > 0) CurrentPage = "downloads";
    }

    private List<string> LinkURLLines() => LinkInput.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
        .Select(value => value.Trim()).Where(value => LinkUrlSafety.TryCreate(value, out _))
        .Distinct(StringComparer.OrdinalIgnoreCase).ToList();

    private string LinkErrorMessage(Exception error) => error is ExternalToolException tool ? tool.Code switch
    {
        "unsupportedURL" => T("link.unsupportedURL"), "videoUnavailable" => T("link.mediaUnavailable"),
        "temporarilyBlocked" => T("link.signInRequired"), "regionalRestriction" => T("link.regionRestricted"),
        "rateLimited" => T("link.rateLimited"), "externalToolUnavailable" => T("link.toolUnavailable"),
        _ => T("link.downloadUnavailable")
    } : T("link.downloadUnavailable");

    private async Task AddResearchNoteAsync(ResearchRecord? record)
    {
        if (record is null || CurrentProject is null) return;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "addResearchReference", ProjectID = CurrentProject.Id.ToString(),
            ResearchRecord = record, Language = _settings.Current.Language
        });
        if (!response.Success)
        {
            ProjectActionStatus = response.ErrorMessage ?? T("research.alreadyInNotes");
            return;
        }
        ApplyDatabase(response.Database);
        ProjectActionStatus = T("research.addedToNotes");
    }

    private async Task FindRelatedMediaAsync(ResearchRecord? record)
    {
        if (record is null) return;
        Query = record.RelatedMediaQueryHints.FirstOrDefault() ?? record.Title;
        SearchScope = "media";
        CurrentPage = "search";
        await RegenerateKeywordsAsync();
        await SearchAsync();
    }

    private async Task AddResearchAsMediaAsync(ResearchRecord? record)
    {
        if (record is null) return;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "researchMediaAsset", ResearchRecord = record, Language = _settings.Current.Language
        });
        var asset = response.Assets?.FirstOrDefault();
        if (!response.Success || asset is null)
        {
            SearchStatus = response.ErrorMessage ?? T("link.downloadUnavailable");
            return;
        }
        Results.Clear();
        _candidateResults.Clear();
        _candidateResults.Add(asset);
        Results.Add(asset);
        SearchScope = "media";
        MediaType = "image";
        SearchStatus = _localization.Text("search.found", 1);
        ResultsView.Refresh();
    }

    private async Task SaveResearchNoteAsync(ResearchReferenceRecord? reference)
    {
        if (reference is null) return;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "updateResearchReference", ResearchReferenceID = reference.Id.ToString(),
            ResearchNote = reference.MyNote, ResearchTags = reference.Tags,
            Language = _settings.Current.Language
        });
        ApplyDatabase(response.Database);
    }

    private async Task DeleteResearchNoteAsync(ResearchReferenceRecord? reference)
    {
        if (reference is null) return;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "deleteResearchReference", ResearchReferenceID = reference.Id.ToString(),
            Language = _settings.Current.Language
        });
        ApplyDatabase(response.Database);
    }

    private async Task RefreshResearchMetadataAsync(ResearchReferenceRecord? reference)
    {
        if (reference is null) return;
        var response = await _core.SendAsync(new CoreRequest
        {
            Action = "refreshResearchReference", ResearchReferenceID = reference.Id.ToString(),
            Language = _settings.Current.Language
        });
        if (!response.Success)
        {
            ProjectActionStatus = response.ErrorMessage ?? T("settings.connectionFailed");
            return;
        }
        ApplyDatabase(response.Database);
    }

    private string QualityLabel(string value) => T($"link.quality.{value}");

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
        foreach (var record in database.Downloads) record.WorkflowSummary = DownloadWorkflowSummary(record);
        Replace(DownloadRecords, database.Downloads.OrderByDescending(x => x.DownloadedAt));
        Replace(ResearchReferences, database.ResearchReferences.OrderByDescending(x => x.AddedAt));
        Replace(SavedSearches, database.SavedSearches.OrderByDescending(x => x.UpdatedAt));
        Replace(ProviderHealth, database.ProviderHealth);
        RefreshWorkspaceSmartCollections();
        RefreshProviderHealthStatuses();
        OnPropertyChanged(nameof(CurrentResearchReferences));
        OnPropertyChanged(nameof(WorkspaceProjectCount));
        OnPropertyChanged(nameof(WorkspaceDownloadCount));
        OnPropertyChanged(nameof(WorkspaceFavoriteCount));
        OnPropertyChanged(nameof(WorkspaceUnknownRightsCount));
        OnPropertyChanged(nameof(WorkspaceAttributionRequiredCount));
        OnPropertyChanged(nameof(WorkspaceMissingLocalMediaCount));
        RefreshProjectDashboard();
        if (CurrentProject is not null) CurrentProject = Projects.FirstOrDefault(x => x.Id == CurrentProject.Id);
    }

    private static void Replace<T>(ObservableCollection<T> target, IEnumerable<T> values)
    {
        target.Clear();
        foreach (var value in values) target.Add(value);
    }

    private bool MatchesProject(Guid? projectId) => CurrentProject is null || projectId == CurrentProject.Id;

    public int WorkspaceProjectCount => Projects.Count;
    public int WorkspaceDownloadCount => DownloadRecords.Count;
    public int WorkspaceFavoriteCount => Favorites.Count;
    public int WorkspaceUnknownRightsCount => Favorites.Count(item =>
        string.Equals(item.LicenseStatusRaw, "UNKNOWN", StringComparison.OrdinalIgnoreCase))
        + DownloadRecords.Count(item => string.Equals(item.Asset?.LicenseStatus, "UNKNOWN", StringComparison.OrdinalIgnoreCase));
    public int WorkspaceAttributionRequiredCount => Favorites.Count(item =>
        string.Equals(item.LicenseStatusRaw, "ATTRIBUTION_REQUIRED", StringComparison.OrdinalIgnoreCase))
        + DownloadRecords.Count(item => string.Equals(item.Asset?.LicenseStatus, "ATTRIBUTION_REQUIRED", StringComparison.OrdinalIgnoreCase));
    public int WorkspaceMissingLocalMediaCount => DownloadRecords.Count(item =>
        !string.IsNullOrWhiteSpace(item.LocalPath) && !File.Exists(item.LocalPath));
    public int ProjectDashboardFavoriteCount => CurrentProject is null ? 0 :
        Favorites.Count(item => item.ProjectID == CurrentProject.Id);
    public int ProjectDashboardDownloadCount => CurrentProject is null ? 0 :
        DownloadRecords.Count(item => item.ProjectID == CurrentProject.Id);
    public int ProjectDashboardResearchReferenceCount => CurrentProject is null ? 0 :
        ResearchReferences.Count(item => item.ProjectID == CurrentProject.Id);
    public int ProjectDashboardResearchNoteCount => CurrentProject is null ? 0 :
        ResearchReferences.Count(item => item.ProjectID == CurrentProject.Id && !string.IsNullOrWhiteSpace(item.MyNote));
    public int ProjectDashboardUnknownRightsCount => CurrentProject is null ? 0 :
        Favorites.Count(item => item.ProjectID == CurrentProject.Id && string.Equals(item.LicenseStatusRaw, "UNKNOWN", StringComparison.OrdinalIgnoreCase))
        + DownloadRecords.Count(item => item.ProjectID == CurrentProject.Id && string.Equals(item.Asset?.LicenseStatus, "UNKNOWN", StringComparison.OrdinalIgnoreCase));
    public int ProjectDashboardAttributionRequiredCount => CurrentProject is null ? 0 :
        Favorites.Count(item => item.ProjectID == CurrentProject.Id && string.Equals(item.LicenseStatusRaw, "ATTRIBUTION_REQUIRED", StringComparison.OrdinalIgnoreCase))
        + DownloadRecords.Count(item => item.ProjectID == CurrentProject.Id && string.Equals(item.Asset?.LicenseStatus, "ATTRIBUTION_REQUIRED", StringComparison.OrdinalIgnoreCase));
    public int ProjectDashboardMissingLocalMediaCount => CurrentProject is null ? 0 :
        DownloadRecords.Count(item => item.ProjectID == CurrentProject.Id && !string.IsNullOrWhiteSpace(item.LocalPath) && !File.Exists(item.LocalPath));

    private void RefreshProjectDashboard()
    {
        OnPropertyChanged(nameof(ProjectDashboardFavoriteCount));
        OnPropertyChanged(nameof(ProjectDashboardDownloadCount));
        OnPropertyChanged(nameof(ProjectDashboardResearchReferenceCount));
        OnPropertyChanged(nameof(ProjectDashboardResearchNoteCount));
        OnPropertyChanged(nameof(ProjectDashboardUnknownRightsCount));
        OnPropertyChanged(nameof(ProjectDashboardAttributionRequiredCount));
        OnPropertyChanged(nameof(ProjectDashboardMissingLocalMediaCount));
    }

    private void RefreshWorkspaceSmartCollections()
    {
        var duplicates = Favorites.Select(item => item.StableID)
            .Concat(DownloadRecords.Select(item => item.StableAssetID))
            .GroupBy(value => value, StringComparer.OrdinalIgnoreCase)
            .Sum(group => Math.Max(0, group.Count() - 1));
        var values = new[]
        {
            new WorkspaceSmartCollection { Id = "downloadedMedia", Title = T("smartCollection.downloadedMedia"), Count = DownloadRecords.Count, Destination = "downloads" },
            new WorkspaceSmartCollection { Id = "recentDownloads", Title = T("smartCollection.recentDownloads"), Count = DownloadRecords.Count(item => item.DownloadedAt >= DateTimeOffset.UtcNow.AddDays(-30)), Destination = "downloads" },
            new WorkspaceSmartCollection { Id = "recentFavorites", Title = T("smartCollection.recentFavorites"), Count = Favorites.Count(item => item.SavedAt >= DateTimeOffset.UtcNow.AddDays(-30)), Destination = "favorites" },
            new WorkspaceSmartCollection { Id = "unknownRights", Title = T("smartCollection.unknownRights"), Count = WorkspaceUnknownRightsCount, Destination = "favorites" },
            new WorkspaceSmartCollection { Id = "attributionRequired", Title = T("smartCollection.attributionRequired"), Count = WorkspaceAttributionRequiredCount, Destination = "favorites" },
            new WorkspaceSmartCollection { Id = "researchWithoutNotes", Title = T("smartCollection.researchWithoutNotes"), Count = ResearchReferences.Count(item => string.IsNullOrWhiteSpace(item.MyNote)), Destination = "projects" },
            new WorkspaceSmartCollection { Id = "recentResearch", Title = T("smartCollection.recentResearch"), Count = ResearchReferences.Count(item => item.UpdatedAt >= DateTimeOffset.UtcNow.AddDays(-30)), Destination = "projects" },
            new WorkspaceSmartCollection { Id = "missingLocalMedia", Title = T("smartCollection.missingLocalMedia"), Count = WorkspaceMissingLocalMediaCount, Destination = "downloads" },
            new WorkspaceSmartCollection { Id = "possibleDuplicates", Title = T("smartCollection.possibleDuplicates"), Count = duplicates, Destination = "projects" }
        };
        Replace(WorkspaceSmartCollections, values);
    }

    private void RefreshProviderHealthStatuses()
    {
        foreach (var provider in Providers)
        {
            var record = ProviderHealth.FirstOrDefault(item => item.ProviderID == provider.Id);
            if (record is null) continue;
            provider.Status = ProviderHealthText(record);
        }
    }

    private string ProviderHealthText(ProviderHealthRecord record)
    {
        var key = record.State switch
        {
            "healthy" => "provider.health.healthy", "rateLimited" => "provider.health.rateLimited",
            "unavailable" => "provider.health.unavailable", "disabled" => "provider.health.disabled",
            "checking" => "provider.health.checking", "limited" => "provider.health.limited",
            "apiKeyRequired" => "provider.health.apiKeyRequired",
            "authenticationRequired" => "provider.health.authenticationRequired",
            "degraded" => "provider.health.degraded", "unknown" => "provider.health.unknown",
            _ => "provider.health.ready"
        };
        var text = T(key);
        if (record.ResponseTimeMilliseconds is { } response) text += $" · {response} ms";
        if (record.TestedAt is { } checkedAt) text += $" · {checkedAt.LocalDateTime:g}";
        return text;
    }

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
                "nasa" or "libraryOfCongress" or "peertube" or "openverse" or "dailymotion" => T("provider.mode.publicAPI"),
                "dareful" or "esa" => T("provider.mode.directSearch"),
                "nationalArchives" or "europeana" or "videvo" or "videezy" or "mixkit" or "coverr" or "vimeo" or "mazwai" or "dvids" or "britishPathe" => T("provider.mode.limited"),
                _ => T("provider.mode.publicInterface")
            };
            provider.Status = hasKey ? T("settings.configured") :
                provider.Id is "nationalArchives" or "europeana" or "videvo" or "videezy" or "mixkit" or "coverr" or "vimeo" or "mazwai" or "dvids" or "britishPathe" ? T("provider.limitedMode") :
                provider.Id is "pexels" or "pixabay" or "youtube" or "dareful" or "esa" ? T("provider.bestEffort") :
                provider.Id is "nasa" or "libraryOfCongress" or "peertube" or "openverse" or "dailymotion" ? T("provider.noKeyRequired") :
                T("provider.available");
            var values = provider.Id is "nationalArchives" or "europeana" or "videvo" or "videezy" or "mixkit" or "coverr" or "vimeo" or "mazwai" or "dvids" or "britishPathe" && !hasKey
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
        OnPropertyChanged(nameof(RightsAuditFilters));
        OnPropertyChanged(nameof(FilteredRightsAuditEntries));
        foreach (var item in LinkItems)
        {
            item.ConfigureQualityLabels(QualityLabel);
            item.ConfigureCreatorLabels(
                value => T($"link.scope.{value}"), value => T($"link.output.{value}"),
                value => T($"link.clip.{value}"));
        }
        RefreshProviderModes();
        RefreshWorkspaceCommands();
        RefreshWorkspaceSmartCollections();
        RefreshProviderHealthStatuses();
        Downloads.RefreshLocalizedStatus();
        foreach (var record in DownloadRecords) record.WorkflowSummary = DownloadWorkflowSummary(record);
        DownloadRecordsView.Refresh();
        SearchStatus = T("search.initialStatus");
        if (CurrentProject is not null && !IsProjectWorking)
            _ = RefreshLocalizedProjectDetailsAsync();
        ScheduleDuplicateReview();
    }

    private async Task RefreshLocalizedProjectDetailsAsync()
    {
        await RefreshRightsAuditAsync();
        await FindDuplicatesAsync();
    }

    private string DownloadWorkflowSummary(DownloadRecord record)
    {
        if (string.IsNullOrWhiteSpace(record.OutputPresetRaw)) return "";
        var values = new List<string>
        {
            $"{T("link.outputFormat")}: {T($"link.output.{record.OutputPresetRaw}")}"
        };
        if (record.ClipStartSeconds is { } start && record.ClipEndSeconds is { } end)
        {
            values.Add($"{T("link.clip.start")}: {Timecode(start)}");
            values.Add($"{T("link.clip.end")}: {Timecode(end)}");
            if (record.ClipDurationSeconds is { } duration)
                values.Add(_localization.Text("link.clip.duration", Timecode(duration)));
        }
        return string.Join(" · ", values);
    }

    private static string Timecode(double seconds) =>
        TimeSpan.FromSeconds(Math.Max(0, Math.Floor(seconds))).ToString(@"hh\:mm\:ss");
}

public sealed record AuditFilterOption(string Id, string Label);
