
require("fileutils")
require(File.expand_path("../../test_helper", __FILE__))

class RepositoriesControllerTest < ActionController::TestCase
  tests RepositoriesController

  fixtures :projects, :users, :roles, :members, :member_roles, :enabled_modules,
           :repositories, :issues, :issue_statuses, :changesets, :changes,
           :issue_categories, :enumerations, :custom_fields, :custom_values, :trackers

  PRJ_ID = 3

  SVN_REPO_PATH = "#{Rails.root.expand_path}/tmp/test/subversion_repository"
  SVN_REPO_URL = "file://#{SVN_REPO_PATH}"

  SUB_SVN_REPO_PATH = "#{Rails.root.expand_path}/tmp/test/sub_subversion_repository"
  SUB_SVN_REPO_URL = "file://#{SUB_SVN_REPO_PATH}"
  SUB_SVN_ID = "sub_svn"

  GIT_REPO_PARENT_PATH = "#{Rails.root.expand_path}/tmp/test/git"
  SUB_GIT_ID = "sub_git"

  def my_system(str)
    `#{str}`
    raise "Failed to execute: #{str}" if ($?.exitstatus != 0)
  end

  def prepare_svn_repos_db
    svn_dump_path = "#{Rails.root.expand_path}/test/fixtures/repositories/subversion_repository.dump.gz"

    [ SVN_REPO_PATH, SUB_SVN_REPO_PATH ].each do |path|
      raise "#{path} exists!" if (File.exists?(path))

      my_system("svnadmin create #{path}")
      my_system("gunzip < #{svn_dump_path} | svnadmin load #{path}")
    end
  end

  def cleanup_svn_repos_db
    [ SVN_REPO_PATH, SUB_SVN_REPO_PATH ].each do |path|
      if (File.exist?(path))
        FileUtils.rmtree(path)
      end
    end
  end

  def prepare_git_db
    raise "#{GIT_REPO_PARENT_PATH} exists!" if (File.exist?(GIT_REPO_PARENT_PATH))

    FileUtils.mkpath(GIT_REPO_PARENT_PATH)
    git_gz_path = "#{Rails.root.expand_path}/test/fixtures/repositories/git_repository.tar.gz"
    my_system("tar xzf #{git_gz_path} -C #{GIT_REPO_PARENT_PATH}")
  end

  def cleanup_git_db
    if (File.exist?(GIT_REPO_PARENT_PATH))
      FileUtils.rmtree(GIT_REPO_PARENT_PATH)
    end
  end

  def prepare_main_repository
    @repository = Repository::Subversion.create(:project => @project, :url => SVN_REPO_URL)
    assert @repository

    @repository.fetch_changesets
    @project.reload
  end

  def prepare_sub_repository
    @sub_repository = Repository::Subversion.create(:project => @project, :url => SUB_SVN_REPO_URL,
                                             :is_default => false, :identifier => SUB_SVN_ID)
    assert @sub_repository

    @sub_repository.fetch_changesets
    @project.reload
  end

  def prepare_git_main_repository
    @git_main_repository = Repository::Git.create(:project => @project,
                                           :url => GIT_REPO_PARENT_PATH + "/git_repository")
    assert @git_main_repository

    @git_main_repository.fetch_changesets
    @project.reload
  end

  def prepare_git_sub_repository
    @git_sub_repository = Repository::Git.create(:project => @project,
                                          :url => GIT_REPO_PARENT_PATH + "/git_repository",
                                          :is_default => false, :identifier => SUB_GIT_ID)
    assert @git_sub_repository

    @git_sub_repository.fetch_changesets
    @project.reload
  end

  def setup
    prepare_svn_repos_db
    prepare_git_db

    Setting.default_language = 'en'
    User.current = nil

    @project = Project.find(PRJ_ID)
  end

  def teardown
    cleanup_git_db
    cleanup_svn_repos_db
  end

  def check_link_to_revision(repo_url)
    # Check link_to_revision output
    # Check link in repository browser table.
    a_attr = { :tag => "a", :attributes => { "class" => "add_subversion_links_link",
        "href" => /^#{Regexp.escape(repo_url)}/ } }
    img_attr = { :tag => "img", :attributes => { "class" => "add_subversion_links_icon" } }
    td_attr = { :tag => "td", :attributes => { "class" => "revision" } }
    assert_tag(img_attr.merge(:parent => a_attr.merge(:parent => td_attr)))

    a_tag = find_tag(a_attr.merge(:child => img_attr, :parent => td_attr))
    rev_link_tag = find_tag(:tag => "a", :before => a_attr.merge(:child => img_attr, :parent => td_attr))
    assert a_tag, "Anchor tag in repository browser table."
    assert rev_link_tag, "Anchor tag before svn_link."

    # rev_link_tag should be '<a href="/projects/subproject1/repository/revisions/11" title="Revision 11">11</a>'
    # So content of child node is revision.
    revision = rev_link_tag.children.first.content
    assert a_tag["href"].match(/\bp=#{revision}\b/), "Svn link should have p=rev parameter."
    assert_equal "tsvn[log][#{revision},#{revision}]", a_tag["rel"], "Svn link should have tsvn log option."

    # Check link in latest revisions table
    assert_tag(img_attr.merge(:parent => a_attr.merge({ :parent => { :tag => "td",
                                                          :attributes => { "class" => "id" },
                                                          :parent => { :tag => "tr",
                                                            :attributes => { "class" => /\bchangeset\b/ } } } })))
  end

  def test_repository
    prepare_main_repository
    get :show, :id => PRJ_ID
    assert_response :success
    check_link_to_revision(SVN_REPO_URL)
  end

  def test_sub_repository
    prepare_main_repository
    prepare_sub_repository

    get :show, :id => PRJ_ID
    assert_response :success
    check_link_to_revision(SVN_REPO_URL)

    get :show, :id => PRJ_ID, :repository_id => SUB_SVN_ID
    assert_response :success
    check_link_to_revision(SUB_SVN_REPO_URL)
  end

  def test_git_repository
    # This plugin should have no side effect to other repository.

    # Check when the project has single main GIT repository
    prepare_git_main_repository
    get :show, :id => PRJ_ID
    assert_response :success

    # Check when the project has main GIT repository and sub Subversion repository.
    prepare_sub_repository
    get :show, :id => PRJ_ID
    assert_response :success

    get :show, :id => PRJ_ID, :repository_id => SUB_SVN_ID
    assert_response :success
    check_link_to_revision(SUB_SVN_REPO_URL)
  end

  def test_git_sub_repository
    # This plugin should have no side effect to other repository.

    # Check when the project has main Subversion repository and sub GIT repository.
    prepare_main_repository
    prepare_git_sub_repository

    get :show, :id => PRJ_ID
    assert_response :success
    check_link_to_revision(SVN_REPO_URL)

    get :show, :id => PRJ_ID, :repository_id => SUB_GIT_ID
    assert_response :success
  end
end
