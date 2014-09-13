require 'spec_helper'

describe ProductsController do
  render_views

  let(:creator) { User.make! }
  let(:collaborator) { User.make! }
  let(:product) { Product.make!(user: creator) }

  describe '#new' do
    it "redirects on signed out" do
      get :new
      expect(response).to redirect_to(new_user_session_path)
    end

    it "is successful when signed in" do
      sign_in creator
      get :new
      expect(response).to be_success
    end
  end

  describe '#show' do
    context 'product is launched' do
      it "is successful" do
        get :show, id: product.slug
        expect(response).to be_success
      end
    end
    context 'product in stealth' do
      let(:product) { Product.make!(launched_at: nil) }

      it "redirects to edit if only name and pitch fields are present" do
        get :show, id: product
        expect(response).to redirect_to(edit_product_path(product))
      end

      it "is successful if fields other than name and pitch are present" do
        product.update_attributes goals: '7'

        get :show, id: product
        expect(response).to be_success
      end
    end
  end

  describe '#edit' do
    it "is successful" do
      product.team_memberships.create(user: product.user, is_core: true)
      sign_in product.user
      get :edit, id: product.slug
      expect(response).to be_success
    end
  end

  describe '#create' do
    before do
      sign_in creator
    end

    context 'with good params' do
      before { post :create, product: { name: 'KJDB', pitch: 'Manage your karaoke life' } }

      it "create's product" do
        expect(assigns(:product)).to be_a(Product)
        expect(assigns(:product)).to be_persisted
      end

      it 'adds user to core team' do
        expect(assigns(:product).core_team).to include(creator)
      end

      it 'should redirect to welcome page' do
        expect(response).to redirect_to(product_welcome_path(assigns(:product)))
      end

      it 'has slug based on name' do
        expect(assigns(:product).slug).to eq('kjdb')
      end

      it 'adds creator to the core team' do
        expect(assigns(:product).core_team).to match_array([creator])
      end

      it 'creates a main discussion thread' do
        expect(Discussion.count).to eq(1)
        expect(assigns(:product).main_thread).to be_persisted
      end

      it 'follows product' do
        expect(assigns(:product).followers.count).to eq(1)
      end
    end

    it 'fails if terms of service not accepted' do
      post :create, product: { name: 'KJDB', pitch: 'Manage your karaoke life' }
      expect(response).to_not be_success
    end

    it 'creates a product with core team' do
      post :create, product: { name: 'KJDB', pitch: 'Manage your karaoke life' }, core_team: [collaborator.id]
      expect(assigns(:product).core_team).to include(collaborator)
    end

    it 'gives auto tip contracts to core team members' do
      post :create, product: { name: 'KJDB', pitch: 'Manage your karaoke life' }, core_team: [collaborator.id]
      expect(assigns(:product).auto_tip_contracts.map(&:user)).to include(collaborator)
    end

    it 'creates an invite for core team members with email' do
      expect {
        post :create, product: { name: 'KJDB', pitch: 'Manage your karaoke life' }, core_team: ['jake@adventure.com'], ownership: { 'jake@adventure.com' => 10 }
      }.to change(Invite, :count).by(1)

      expect(
        Invite.find_by(invitee_email: 'jake@adventure.com').via.name
      ).to eq('KJDB')
    end

    it 'creates invite with tip to collaborator' do
      post :create, product: { name: 'KJDB', pitch: 'Manage your karaoke life' }, ownership: { collaborator.id => 10 }

      invite = Invite.find_by(invitee_id: collaborator.id)
      expect(invite.tip_cents).to eq(60000)
      expect(invite.via.name).to eq('KJDB')
      expect(invite.core_team?).to be_true
    end

    it 'mints founder coins' do
      post :create, product: { name: 'KJDB', pitch: 'Manage your karaoke life' }, core_team: ['jake@adventure.com'], ownership: { 'jake@adventure.com' => 10 }

      expect(
        TransactionLogEntry.find_by(product_id: assigns(:product).id)
      ).to have_attributes(
        action: 'minted',
        cents: 600000
      )
    end
  end

  describe '#update' do
    before do
      sign_in creator
    end

    it 'updates all fields' do
      info_fields = Product::INFO_FIELDS.each_with_object({}) do |field, h|
        h[field.to_sym] = field
      end

      attrs = {
        name: 'KJDB',
        pitch: 'Manage your karaoke life',
        description: 'it is good.'
      }.merge(info_fields)

      patch :update, id: product, product: attrs
      expect(product.reload).to have_attributes(attrs)
    end
  end

  describe '#launch' do
    let(:product) { Product.make!(launched_at: nil, user: creator) }

    before do
      sign_in creator
    end

    it "redirects to product slug" do
      patch :launch, product_id: product
      expect(response).to redirect_to(product_path(product.reload.slug))
    end

    it 'queues job' do
      expect {
        patch :launch, product_id: product
      }.to change(ApplyForPitchWeek.jobs, :size).by(1)
    end

    it 'sets product to launched' do
      patch :launch, product_id: product
      expect(product.reload.launched_at.to_i).to be_within(2).of(Time.now.to_i)
    end
  end

  describe '#follow' do
    let(:product) { Product.make!(user: creator) }

    before do
      sign_in collaborator
    end

    it 'publishes activity' do
      expect {
        patch :follow, product_id: product
      }.to change(Activity, :count).by(1)
    end
  end
end
